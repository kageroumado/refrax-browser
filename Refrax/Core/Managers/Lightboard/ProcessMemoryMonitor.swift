import Darwin
import Foundation
import Observation
import OSLog
import WebKit

// MARK: - Web Process Info

/// Snapshot of a single web content process with its associated tabs.
struct WebProcessSnapshot: Identifiable, Equatable {
    /// Process identifier.
    let pid: pid_t

    /// Physical memory footprint in bytes (Mach phys_footprint).
    let physicalFootprint: UInt64

    /// Scheduling state of the process.
    let state: _WKProcessState

    /// Content-level state (prewarmed, cached, active).
    let contentState: _WKWebContentProcessState

    /// Cumulative CPU time (user + system) in seconds.
    let totalCPUTime: TimeInterval

    /// Tab page IDs hosted in this process.
    let tabPageIDs: [UUID]

    var id: pid_t { pid }

    /// Physical footprint in megabytes.
    var memoryMB: Int {
        Int(physicalFootprint / 1_024 / 1_024)
    }

    /// Estimated per-tab memory when multiple tabs share this process.
    var estimatedPerTabMemory: UInt64 {
        guard tabPageIDs.count > 0 else { return physicalFootprint }
        return physicalFootprint / UInt64(tabPageIDs.count)
    }

    static func == (lhs: WebProcessSnapshot, rhs: WebProcessSnapshot) -> Bool {
        lhs.pid == rhs.pid &&
            lhs.physicalFootprint == rhs.physicalFootprint &&
            lhs.state == rhs.state &&
            lhs.tabPageIDs == rhs.tabPageIDs
    }
}

// MARK: - Memory Data Point

/// A single data point for the rolling memory graph.
struct MemoryDataPoint: Equatable {
    let timestamp: Date
    let webMB: Int
    let gpuMB: Int
    let appMB: Int
    let unmappedMB: Int
}

// MARK: - Process Memory Monitor

/// Monitors WebKit process memory using private `_WKProcessInfo` APIs.
///
/// Provides per-process memory with tab-to-process mapping, accurate
/// physical footprint (same as Activity Monitor), and Refrax app memory.
/// Polling is gated on UI visibility via reference counting.
///
/// ## Key differences from previous implementation
///
/// - Uses `WKProcessPool._webContentProcessInfo` instead of `proc_pidinfo`
/// - Reports `physicalFootprint` (Mach phys_footprint) not `pti_resident_size`
/// - Maps processes to tabs via `_WKWebContentProcessInfo.webViews`
/// - Tracks per-process snapshots, not just aggregate totals
/// - Includes Refrax app process memory
@Observable
final class ProcessMemoryMonitor {
    // MARK: - Observable Properties

    /// Total memory used by WebContent processes (in bytes).
    private(set) var totalWebContentMemory: UInt64 = 0

    /// Memory used by the GPU process (in bytes).
    private(set) var gpuProcessMemory: UInt64 = 0

    /// Memory used by the Refrax app process (in bytes).
    private(set) var appProcessMemory: UInt64 = 0

    /// Number of active WebContent processes.
    private(set) var activeWebProcessCount: Int = 0

    /// Per-process snapshots with tab mapping.
    private(set) var processSnapshots: [WebProcessSnapshot] = []

    /// Memory from web processes that couldn't be mapped to any tab (prewarmed/orphan).
    private(set) var unmappedProcessMemory: UInt64 = 0

    /// Last update timestamp.
    private(set) var lastUpdated: Date?

    /// Version counter for memory history updates (triggers view rebuilds).
    private(set) var memoryHistoryVersion: Int = 0

    // MARK: - Deprecated compatibility

    /// Total memory used by WebContent processes (in MB).
    var webContentMemoryMB: Int { Int(totalWebContentMemory / 1_024 / 1_024) }

    /// Memory used by the GPU process (in MB).
    var gpuProcessMemoryMB: Int { Int(gpuProcessMemory / 1_024 / 1_024) }

    // MARK: - Configuration

    /// Interval between memory polls when monitoring is active.
    let pollingInterval: TimeInterval = 3.0

    // MARK: - Private

    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    @ObservationIgnored
    private unowned let pagePool: WebPagePool

    @ObservationIgnored
    private var monitorCount = 0

    /// Maps PIDs to sequential human-friendly process numbers.
    @ObservationIgnored
    private var processNumberMap: [pid_t: Int] = [:]

    /// Counter for assigning sequential process numbers.
    @ObservationIgnored
    private var nextProcessNumber = 1

    /// Rolling history of memory data points (max 60, ~3 minutes at 3s intervals).
    @ObservationIgnored
    private(set) var memoryHistory: [MemoryDataPoint] = []

    /// Maximum number of history points to retain.
    @ObservationIgnored
    private let maxHistoryPoints = 60

    // MARK: - Initialization

    init(pagePool: WebPagePool) {
        self.pagePool = pagePool
    }

    // MARK: - Monitoring Control

    /// Starts periodic memory monitoring.
    ///
    /// Uses reference counting to support multiple monitors. Monitoring
    /// begins when the first caller starts and stops when the last stops.
    func startMonitoring() {
        monitorCount += 1
        guard monitorCount == 1 else { return }

        updateMemoryStats()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollingInterval ?? 5.0))
                guard !Task.isCancelled else { break }
                self?.updateMemoryStats()
            }
        }
    }

    /// Stops memory monitoring for the calling observer.
    func stopMonitoring() {
        guard monitorCount > 0 else { return }
        monitorCount -= 1
        guard monitorCount == 0 else { return }

        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Requests an immediate memory update.
    func requestUpdate() {
        updateMemoryStats()
    }

    // MARK: - WKProcessPool Wrappers

    // MARK: - Memory Reading

    /// Updates memory statistics using WebKit's process info APIs.
    private func updateMemoryStats() {
        let webViewToTabPageID = buildWebViewMapping()

        let processInfos = WKProcessPoolBridge.webContentProcessInfo()

        var snapshots: [WebProcessSnapshot] = []
        var totalMem: UInt64 = 0
        var unmappedMem: UInt64 = 0
        var activeCount = 0

        for info in processInfos {
            guard let contentInfo = info as? _WKWebContentProcessInfo else {
                Logger.debug("[Lightboard] Process PID \(info.pid) is not _WKWebContentProcessInfo, skipping", category: Logger.lightboard)
                continue
            }

            let footprint = UInt64(contentInfo.physicalFootprint)
            let cpuTime = contentInfo.totalUserCPUTime + contentInfo.totalSystemCPUTime

            var tabIDs: [UUID] = []
            for webView in contentInfo.webViews {
                let viewID = ObjectIdentifier(webView)
                if let tabPageID = webViewToTabPageID[viewID] {
                    tabIDs.append(tabPageID)
                }
            }

            if tabIDs.isEmpty {
                Logger.debug(
                    "[Lightboard] Process PID \(contentInfo.pid): \(footprint / 1_024 / 1_024) MB, prewarmed/orphan (webViews=\(contentInfo.webViews.count), no matched tabs), skipping",
                    category: Logger.lightboard
                )
                unmappedMem += footprint
                continue
            }

            let snapshot = WebProcessSnapshot(
                pid: contentInfo.pid,
                physicalFootprint: footprint,
                state: contentInfo.state,
                contentState: contentInfo.webContentState,
                totalCPUTime: cpuTime,
                tabPageIDs: tabIDs
            )
            snapshots.append(snapshot)

            if contentInfo.webContentState == .active {
                activeCount += 1
                totalMem += footprint
            }

            assignProcessNumber(for: contentInfo.pid)

            Logger.debug(
                "[Lightboard] Process PID \(contentInfo.pid): \(footprint / 1_024 / 1_024) MB, tabs=\(tabIDs.count), webViews=\(contentInfo.webViews.count), CPU=\(String(format: "%.1f", cpuTime))s",
                category: Logger.lightboard
            )
        }

        let gpuInfo = WKProcessPoolBridge.gpuProcessInfo()
        let gpuMem: UInt64
        if let gpuInfo {
            gpuMem = UInt64(gpuInfo.physicalFootprint)
            Logger.debug("[Lightboard] GPU process PID \(gpuInfo.pid): \(gpuMem / 1_024 / 1_024) MB", category: Logger.lightboard)
        } else {
            gpuMem = 0
        }

        let appMem = readAppProcessMemory()

        Logger.debug(
            "[Lightboard] Summary: \(snapshots.count) web processes (\(activeCount) active), unmapped=\(unmappedMem / 1_024 / 1_024) MB, web=\(totalMem / 1_024 / 1_024) MB, GPU=\(gpuMem / 1_024 / 1_024) MB, app=\(appMem / 1_024 / 1_024) MB",
            category: Logger.lightboard
        )

        processSnapshots = snapshots
        totalWebContentMemory = totalMem
        unmappedProcessMemory = unmappedMem
        gpuProcessMemory = gpuMem
        appProcessMemory = appMem
        activeWebProcessCount = activeCount

        let dataPoint = MemoryDataPoint(
            timestamp: Date(),
            webMB: Int(totalMem / 1_024 / 1_024),
            gpuMB: Int(gpuMem / 1_024 / 1_024),
            appMB: Int(appMem / 1_024 / 1_024),
            unmappedMB: Int(unmappedMem / 1_024 / 1_024)
        )
        memoryHistory.append(dataPoint)
        if memoryHistory.count > maxHistoryPoints {
            memoryHistory.removeFirst(memoryHistory.count - maxHistoryPoints)
        }
        memoryHistoryVersion += 1

        lastUpdated = Date()

        let activePIDs = Set(snapshots.map(\.pid))
        processNumberMap = processNumberMap.filter { activePIDs.contains($0.key) }
        if processNumberMap.isEmpty {
            nextProcessNumber = 1
        }
    }

    /// Builds a mapping from WKWebView ObjectIdentifier → TabPage.ID.
    ///
    /// This allows us to match the `webViews` array from `_WKWebContentProcessInfo`
    /// (which contains WKWebView instances) back to our TabPage model.
    private func buildWebViewMapping() -> [ObjectIdentifier: UUID] {
        var map: [ObjectIdentifier: UUID] = [:]
        for (tabPageID, webPage) in pagePool.activePages {
            let viewID = ObjectIdentifier(webPage.backingWebView as WKWebView)
            map[viewID] = tabPageID
        }
        return map
    }

    /// Assigns a sequential process number if this PID hasn't been seen before.
    private func assignProcessNumber(for pid: pid_t) {
        guard processNumberMap[pid] == nil else { return }
        processNumberMap[pid] = nextProcessNumber
        nextProcessNumber += 1
    }

    /// Returns a human-friendly name for a process, e.g. "Process 1".
    func processName(for pid: pid_t) -> String {
        if let number = processNumberMap[pid] {
            return "Process \(number)"
        }
        return "Process ?"
    }

    /// Reads the Refrax app process physical footprint using Mach task info.
    private func readAppProcessMemory() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rawPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            Logger.warning("[Lightboard] Failed to read app process memory: kern_return \(result)", category: Logger.lightboard)
            return 0
        }

        return UInt64(info.phys_footprint)
    }

    // MARK: - Process Control

    /// Unloads all tabs in a process by removing their WebPages from the pool.
    ///
    /// This is the proper way to free memory — it removes the WebPage from
    /// `activePages`, closes the history entry, and releases all resources.
    /// When the user navigates back to the tab, `page(for:)` creates a fresh
    /// WebPage with a new process.
    ///
    /// - Returns: The tab page IDs that were unloaded.
    @discardableResult
    func unloadProcess(_ pid: pid_t) -> [UUID] {
        var unloadedIDs: [UUID] = []

        for (tabPageID, webPage) in pagePool.activePages {
            if webPage.backingWebView._webProcessIdentifier == pid {
                unloadedIDs.append(tabPageID)
            }
        }

        guard !unloadedIDs.isEmpty else {
            Logger.warning("[Lightboard] No WebViews found for PID \(pid)", category: Logger.lightboard)
            return []
        }

        for tabPageID in unloadedIDs {
            if let webPage = pagePool.existingPage(for: tabPageID) {
                let tabPage = webPage.tabPage
                Logger.info("[Lightboard] Unloading tab '\(tabPage.title.prefix(20))' (PID \(pid))", category: Logger.lightboard)
                pagePool.removePage(for: tabPage)
            }
        }

        requestUpdate()
        return unloadedIDs
    }

    // MARK: - Lookup

    /// Returns the process snapshot for a given tab page ID.
    func processSnapshot(for tabPageID: UUID) -> WebProcessSnapshot? {
        processSnapshots.first { $0.tabPageIDs.contains(tabPageID) }
    }

    /// Returns estimated memory in bytes for a specific tab.
    ///
    /// If the tab's process hosts multiple tabs, returns an equal share.
    func estimatedMemory(for tabPageID: UUID) -> UInt64 {
        guard let snapshot = processSnapshot(for: tabPageID) else { return 0 }
        return snapshot.estimatedPerTabMemory
    }
}

// MARK: - Computed Properties

extension ProcessMemoryMonitor {
    /// Total memory across all browser processes (WebContent + GPU + App + unmapped).
    var totalBrowserMemoryMB: Int {
        Int((totalWebContentMemory + unmappedProcessMemory + gpuProcessMemory + appProcessMemory) / 1_024 / 1_024)
    }
}
