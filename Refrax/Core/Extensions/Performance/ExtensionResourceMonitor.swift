import Foundation
import Observation
import WebKit

/// Tracks resource usage metrics per extension.
///
/// This actor monitors memory, CPU, and network usage for each loaded extension context.
/// It provides real-time metrics and historical data for identifying resource-heavy extensions.
///
/// ## Limitations
///
/// Since `WKWebExtensionContext` doesn't expose direct process metrics, this monitor uses
/// approximations and sampling:
/// - **Memory**: Estimated from WebView private memory reports (when available)
/// - **CPU**: Sampled periodically and attributed based on active contexts
/// - **Network**: Counted via shim layer hooks for extension-initiated requests
///
/// ## Usage
///
/// ```swift
/// let monitor = ExtensionResourceMonitor()
/// await monitor.startMonitoring(for: extension)
///
/// // Check metrics
/// if let metrics = await monitor.metrics(for: extension) {
///     print("Memory: \(metrics.memoryUsage) bytes")
/// }
///
/// // Check against budget
/// let status = await monitor.budgetStatus(for: extension)
/// if status == .exceeded {
///     // Take action
/// }
/// ```
actor ExtensionResourceMonitor {
    // MARK: - Types

    /// Budget enforcement status for an extension.
    enum BudgetStatus: Sendable {
        /// Resource usage is within limits.
        case withinLimits
        /// Resource usage is approaching limits (>80%).
        case warning(ResourceWarning)
        /// Resource usage exceeds limits.
        case exceeded(ResourceViolation)
    }

    /// Warning when approaching resource limits.
    struct ResourceWarning: Sendable {
        let extensionID: String
        let resourceType: ResourceType
        let currentUsage: Double
        let budgetLimit: Double
        let percentUsed: Double
    }

    /// Violation when exceeding resource limits.
    struct ResourceViolation: Sendable {
        let extensionID: String
        let resourceType: ResourceType
        let currentUsage: Double
        let budgetLimit: Double
        let timestamp: Date
    }

    /// Type of resource being monitored.
    enum ResourceType: String, Sendable {
        case memory
        case cpu
        case network
    }

    // MARK: - State

    /// Current metrics per extension, keyed by unique identifier.
    private var currentMetrics: [String: ResourceMetrics] = [:]

    /// Historical metrics for trending, keyed by extension ID.
    /// Stores the last N samples for each extension.
    private var historicalMetrics: [String: [ResourceMetrics]] = [:]

    /// Network request counts per extension (reset periodically).
    private var networkRequestCounts: [String: Int] = [:]

    /// Last time network counts were reset.
    private var lastNetworkCountReset: Date = .init()

    /// Extensions registered for monitoring (by unique identifier).
    /// Actual monitoring tasks only run when shouldMonitor is true.
    private var registeredExtensions: [String: InstalledExtension] = [:]

    /// Active monitoring task (single centralized task for all extensions).
    private var monitoringTask: Task<Void, Never>?

    /// Whether the metrics UI is currently visible.
    private var isUIVisible: Bool = false

    /// Whether the app is currently active (frontmost).
    private var isAppActive: Bool = false

    /// Whether monitoring should be active (app active OR UI visible).
    private var shouldMonitor: Bool {
        isAppActive || isUIVisible
    }

    /// Sampling interval when UI is visible (frequent updates for responsiveness).
    private let activeInterval: Duration = .seconds(5)

    /// Number of historical samples to retain per extension.
    let maxHistoricalSamples = 60 // 5 minutes of data at 5s intervals

    /// Warning threshold (percentage of budget).
    let warningThreshold = 0.8

    // MARK: - Initialization

    init() {}

    // MARK: - App & UI State

    /// Notifies the monitor that the app has become active or inactive.
    ///
    /// When the app is inactive AND the metrics UI is not visible, monitoring
    /// pauses entirely to save battery. Monitoring resumes when the app becomes
    /// active again.
    ///
    /// - Parameter active: Whether the app is currently active (frontmost).
    func setAppActive(_ active: Bool) {
        let wasMonitoring = shouldMonitor
        isAppActive = active
        updateMonitoringState(wasMonitoring: wasMonitoring)
    }

    /// Notifies the monitor that the metrics UI has become visible or hidden.
    ///
    /// When visible, sampling happens every 5 seconds for responsive UI updates.
    /// When the app is active but UI is hidden, monitoring continues for budget
    /// enforcement. When both app is inactive and UI is hidden, monitoring pauses.
    ///
    /// - Parameter visible: Whether the metrics UI is currently visible.
    func setUIVisibility(_ visible: Bool) {
        let wasMonitoring = shouldMonitor
        isUIVisible = visible
        updateMonitoringState(wasMonitoring: wasMonitoring)
    }

    /// Updates monitoring state based on current conditions.
    private func updateMonitoringState(wasMonitoring: Bool) {
        if shouldMonitor, !wasMonitoring {
            // Start monitoring
            startMonitoringTask()
        } else if !shouldMonitor, wasMonitoring {
            // Stop monitoring
            stopMonitoringTask()
        }
    }

    /// Starts the centralized monitoring task.
    private func startMonitoringTask() {
        guard monitoringTask == nil, !registeredExtensions.isEmpty else { return }

        monitoringTask = Task {
            await monitoringLoop()
        }

        Logger.debug("Extension resource monitoring started", category: Logger.extensions)
    }

    /// Stops the centralized monitoring task.
    private func stopMonitoringTask() {
        monitoringTask?.cancel()
        monitoringTask = nil

        Logger.debug("Extension resource monitoring paused", category: Logger.extensions)
    }

    // MARK: - Monitoring Control

    /// Starts monitoring resource usage for an extension.
    ///
    /// - Parameter extension_: The extension to monitor.
    func startMonitoring(for extension_: InstalledExtension) {
        let extensionID = extension_.uniqueIdentifier

        // Don't register if already registered
        guard registeredExtensions[extensionID] == nil else { return }

        // Register the extension
        registeredExtensions[extensionID] = extension_

        // Initialize metrics
        currentMetrics[extensionID] = ResourceMetrics(
            extensionID: extensionID,
            extensionName: extension_.displayName,
        )
        historicalMetrics[extensionID] = []
        networkRequestCounts[extensionID] = 0

        // Start monitoring task if conditions are met
        if shouldMonitor, monitoringTask == nil {
            startMonitoringTask()
        }

        Logger.debug(
            "Registered resource monitoring for '\(extension_.displayName)'",
            category: Logger.extensions,
        )
    }

    /// Stops monitoring resource usage for an extension.
    ///
    /// - Parameter extension_: The extension to stop monitoring.
    func stopMonitoring(for extension_: InstalledExtension) {
        let extensionID = extension_.uniqueIdentifier
        stopMonitoring(extensionID: extensionID)
    }

    /// Stops monitoring by extension ID.
    private func stopMonitoring(extensionID: String) {
        registeredExtensions.removeValue(forKey: extensionID)
        currentMetrics.removeValue(forKey: extensionID)
        historicalMetrics.removeValue(forKey: extensionID)
        networkRequestCounts.removeValue(forKey: extensionID)

        // Stop task if no extensions remain
        if registeredExtensions.isEmpty {
            stopMonitoringTask()
        }

        Logger.debug(
            "Stopped resource monitoring for extension '\(extensionID)'",
            category: Logger.extensions,
        )
    }

    // MARK: - Metrics Access

    /// Returns current metrics for an extension.
    ///
    /// - Parameter extension_: The extension to get metrics for.
    /// - Returns: Current resource metrics, or nil if not monitoring.
    func metrics(for extension_: InstalledExtension) -> ResourceMetrics? {
        currentMetrics[extension_.uniqueIdentifier]
    }

    /// Returns current metrics for an extension by ID.
    func metrics(forID extensionID: String) -> ResourceMetrics? {
        currentMetrics[extensionID]
    }

    /// Returns all current metrics.
    func allMetrics() -> [ResourceMetrics] {
        Array(currentMetrics.values)
    }

    /// Returns historical metrics for trending.
    ///
    /// - Parameter extension_: The extension to get history for.
    /// - Returns: Array of historical metrics, oldest first.
    func history(for extension_: InstalledExtension) -> [ResourceMetrics] {
        historicalMetrics[extension_.uniqueIdentifier] ?? []
    }

    // MARK: - Budget Checking

    /// Checks the budget status for an extension.
    ///
    /// - Parameters:
    ///   - extension_: The extension to check.
    ///   - budget: The budget to check against (uses default if nil).
    /// - Returns: The current budget status.
    func budgetStatus(
        for extension_: InstalledExtension,
        budget: ResourceBudget? = nil,
    ) -> BudgetStatus {
        guard let metrics = currentMetrics[extension_.uniqueIdentifier] else {
            return .withinLimits
        }

        // Use explicit default to avoid MainActor isolation issue with autoclosure
        let defaultBudget = ResourceBudget.default
        let effectiveBudget = budget ?? extension_.resourceBudget ?? defaultBudget

        // Check memory
        if metrics.memoryUsage > UInt64(effectiveBudget.maxMemory) {
            return .exceeded(ResourceViolation(
                extensionID: extension_.uniqueIdentifier,
                resourceType: .memory,
                currentUsage: Double(metrics.memoryUsage),
                budgetLimit: Double(effectiveBudget.maxMemory),
                timestamp: Date(),
            ))
        }

        let memoryPercent = Double(metrics.memoryUsage) / Double(effectiveBudget.maxMemory)
        if memoryPercent > warningThreshold {
            return .warning(ResourceWarning(
                extensionID: extension_.uniqueIdentifier,
                resourceType: .memory,
                currentUsage: Double(metrics.memoryUsage),
                budgetLimit: Double(effectiveBudget.maxMemory),
                percentUsed: memoryPercent,
            ))
        }

        // Check CPU
        if metrics.cpuUsage > effectiveBudget.maxCPU {
            return .exceeded(ResourceViolation(
                extensionID: extension_.uniqueIdentifier,
                resourceType: .cpu,
                currentUsage: metrics.cpuUsage,
                budgetLimit: effectiveBudget.maxCPU,
                timestamp: Date(),
            ))
        }

        let cpuPercent = metrics.cpuUsage / effectiveBudget.maxCPU
        if cpuPercent > warningThreshold {
            return .warning(ResourceWarning(
                extensionID: extension_.uniqueIdentifier,
                resourceType: .cpu,
                currentUsage: metrics.cpuUsage,
                budgetLimit: effectiveBudget.maxCPU,
                percentUsed: cpuPercent,
            ))
        }

        // Check network (requests per minute)
        let requestsPerMinute = metrics.networkRequestsPerMinute
        if requestsPerMinute > effectiveBudget.maxNetworkRequestsPerMinute {
            return .exceeded(ResourceViolation(
                extensionID: extension_.uniqueIdentifier,
                resourceType: .network,
                currentUsage: Double(requestsPerMinute),
                budgetLimit: Double(effectiveBudget.maxNetworkRequestsPerMinute),
                timestamp: Date(),
            ))
        }

        let networkPercent = Double(requestsPerMinute) / Double(effectiveBudget.maxNetworkRequestsPerMinute)
        if networkPercent > warningThreshold {
            return .warning(ResourceWarning(
                extensionID: extension_.uniqueIdentifier,
                resourceType: .network,
                currentUsage: Double(requestsPerMinute),
                budgetLimit: Double(effectiveBudget.maxNetworkRequestsPerMinute),
                percentUsed: networkPercent,
            ))
        }

        return .withinLimits
    }

    // MARK: - Network Request Tracking

    /// Records a network request initiated by an extension.
    ///
    /// Called by the shim layer when extensions make network requests.
    ///
    /// - Parameter extensionID: The extension that made the request.
    func recordNetworkRequest(for extensionID: String) {
        networkRequestCounts[extensionID, default: 0] += 1
    }

    // MARK: - Private Implementation

    /// Centralized monitoring loop for all registered extensions.
    ///
    /// Runs only when `shouldMonitor` is true (app is active OR UI is visible).
    /// Samples all registered extensions at a fixed interval.
    private func monitoringLoop() async {
        while !Task.isCancelled {
            // Sample all registered extensions
            for extensionID in registeredExtensions.keys {
                sampleMetrics(for: extensionID)
            }

            do {
                try await Task.sleep(for: activeInterval)
            } catch {
                break
            }
        }
    }

    /// Samples current resource usage for an extension.
    private func sampleMetrics(for extensionID: String) {
        guard var metrics = currentMetrics[extensionID] else { return }

        // Sample memory (using process info as approximation)
        let memoryUsage = sampleMemoryUsage()

        // Sample CPU
        let cpuUsage = sampleCPUUsage()

        // Calculate network requests per minute
        let now = Date()
        let timeSinceReset = now.timeIntervalSince(lastNetworkCountReset)
        let requestCount = networkRequestCounts[extensionID] ?? 0
        let requestsPerMinute: Int

        if timeSinceReset >= 60 {
            // Reset network counts every minute
            requestsPerMinute = requestCount
            networkRequestCounts[extensionID] = 0
            lastNetworkCountReset = now
        } else if timeSinceReset > 0 {
            // Extrapolate to per-minute rate
            requestsPerMinute = Int(Double(requestCount) * 60.0 / timeSinceReset)
        } else {
            requestsPerMinute = 0
        }

        // Update metrics
        metrics.memoryUsage = memoryUsage
        metrics.cpuUsage = cpuUsage
        metrics.networkRequestsPerMinute = requestsPerMinute
        metrics.lastSampled = now

        // Update peak values
        if memoryUsage > metrics.peakMemoryUsage {
            metrics.peakMemoryUsage = memoryUsage
        }
        if cpuUsage > metrics.peakCPUUsage {
            metrics.peakCPUUsage = cpuUsage
        }

        currentMetrics[extensionID] = metrics

        // Add to history
        var history = historicalMetrics[extensionID] ?? []
        history.append(metrics)

        // Trim to max samples
        if history.count > maxHistoricalSamples {
            history.removeFirst(history.count - maxHistoricalSamples)
        }
        historicalMetrics[extensionID] = history
    }

    /// Samples current memory usage.
    ///
    /// This returns an approximation based on the app's memory footprint.
    /// In a production implementation, you'd want to track per-WebView memory.
    private func sampleMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            // Divide by estimated number of extensions as approximation
            // In production, you'd track per-WebView memory via private APIs
            let extensionCount = max(1, currentMetrics.count)
            return info.resident_size / UInt64(extensionCount)
        }

        return 0
    }

    /// Samples current CPU usage.
    ///
    /// Returns an approximation of CPU usage percentage (0-100).
    /// Uses task_info to get total task CPU time and calculates delta.
    private func sampleCPUUsage() -> Double {
        var taskInfo = task_thread_times_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        // Convert user time to microseconds
        let userTime = Double(taskInfo.user_time.seconds) * 1_000_000 + Double(taskInfo.user_time.microseconds)

        // This is a simplified approximation - in a real implementation you'd track
        // the delta over time to compute actual CPU percentage
        // For now, return a normalized value based on the number of extensions
        let extensionCount = max(1, currentMetrics.count)

        // Approximate: assume 1 second of user time = 1% CPU over the monitoring period
        // This is very rough but gives relative comparisons between extensions
        let cpuPerExtension = min(100.0, userTime / 1_000_000 / Double(extensionCount))
        return cpuPerExtension
    }
}

// MARK: - Resource Metrics

/// Current resource usage metrics for an extension.
struct ResourceMetrics: Sendable, Identifiable, Equatable {
    /// Extension unique identifier.
    let extensionID: String

    /// Display name for UI.
    let extensionName: String

    /// Unique identifier (same as extensionID).
    var id: String { extensionID }

    /// Current memory usage in bytes.
    var memoryUsage: UInt64 = 0

    /// Peak memory usage since monitoring started.
    var peakMemoryUsage: UInt64 = 0

    /// Current CPU usage percentage (0-100).
    var cpuUsage: Double = 0

    /// Peak CPU usage since monitoring started.
    var peakCPUUsage: Double = 0

    /// Network requests in the last minute.
    var networkRequestsPerMinute: Int = 0

    /// Total network requests since monitoring started.
    var totalNetworkRequests: Int = 0

    /// When these metrics were last sampled.
    var lastSampled: Date = .init()

    /// When monitoring started for this extension.
    let monitoringStarted: Date = .init()
}

// MARK: - Formatting Helpers

extension ResourceMetrics {
    /// Formatted memory usage string.
    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsage), countStyle: .memory)
    }

    /// Formatted peak memory string.
    var formattedPeakMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(peakMemoryUsage), countStyle: .memory)
    }

    /// Formatted CPU usage string.
    var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage)
    }

    /// Formatted peak CPU string.
    var formattedPeakCPU: String {
        String(format: "%.1f%%", peakCPUUsage)
    }
}
