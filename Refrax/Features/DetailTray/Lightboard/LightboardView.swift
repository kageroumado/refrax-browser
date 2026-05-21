import SwiftUI

// MARK: - Lightboard View

/// Dashboard view for monitoring tab health and resources.
///
/// Displays:
/// - Header stats bar with memory and tab counts
/// - Filter and sort controls
/// - List of tabs grouped by space with health indicators
/// - Bulk action buttons
struct LightboardView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(WebPagePool.self) private var pagePool
    @Environment(TabHealthProvider.self) private var healthProvider
    @Environment(ProcessMemoryMonitor.self) private var memoryMonitor

    @State private var selectedIDs: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var expandedIDs: Set<UUID> = []
    @State private var showingMemoryInfo = false

    var body: some View {
        Group {
            if healthProvider.snapshots.isEmpty {
                emptyState
            } else {
                tabListView
            }
        }
        .safeAreaBar(edge: .top) { header }
        .safeAreaBar(edge: .bottom) { footer }
        .onAppear {
            healthProvider.startObserving()
            memoryMonitor.startMonitoring()
        }
        .onDisappear {
            healthProvider.stopObserving()
            memoryMonitor.stopMonitoring()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            DetailTrayHeader(
                title: "Lightboard",
                currentMode: .lightboard,
                onClose: { windowState.hideDetailTray() },
            )

            // Stats bar
            statsBar
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            // Filter bar
            filterBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                StatBadge(
                    icon: "memorychip",
                    value: "\(memoryMonitor.totalBrowserMemoryMB) MB",
                    color: .blue,
                )

                StatBadge(
                    icon: "square.on.square",
                    value: "\(healthProvider.totalTabCount) tabs",
                    color: .secondary,
                )

                if healthProvider.crashedTabCount > 0 {
                    StatBadge(
                        icon: "exclamationmark.triangle.fill",
                        value: "\(healthProvider.crashedTabCount) crashed",
                        color: .red,
                    )
                }
            }

            HStack(spacing: 4) {
                Text("Web: \(memoryMonitor.webContentMemoryMB) MB \u{00B7} GPU: \(memoryMonitor.gpuProcessMemoryMB) MB \u{00B7} App: \(Int(memoryMonitor.appProcessMemory / 1_024 / 1_024)) MB")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Button {
                    showingMemoryInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingMemoryInfo) {
                    memoryInfoPopover
                }
            }

            if memoryMonitor.activeWebProcessCount > 0 {
                Text("\(memoryMonitor.activeWebProcessCount) web process\(memoryMonitor.activeWebProcessCount == 1 ? "" : "es")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                graphLegendItem(label: "Web", color: .blue)
                graphLegendItem(label: "GPU", color: .green)
                graphLegendItem(label: "App", color: .orange)

                Text("(MB)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            MemoryGraphView(
                history: memoryMonitor.memoryHistory,
                historyVersion: memoryMonitor.memoryHistoryVersion
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            // Sort picker
            Menu {
                ForEach(TabHealthSortMode.allCases) { mode in
                    Button(mode.rawValue) {
                        healthProvider.sortMode = mode
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Sort: \(healthProvider.sortMode.rawValue)")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .adaptiveBackground(.subtle, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Filter picker
            Menu {
                ForEach(TabHealthFilter.allCases) { filter in
                    Button(filter.rawValue) {
                        healthProvider.processFilter = nil
                        healthProvider.filter = filter
                    }
                }

                let processes = healthProvider.availableProcesses
                if !processes.isEmpty {
                    Divider()

                    Menu("By Process") {
                        ForEach(processes, id: \.pid) { process in
                            Button("\(process.name) (\(process.tabCount) tab\(process.tabCount == 1 ? "" : "s"))") {
                                healthProvider.filter = .all
                                healthProvider.processFilter = process.pid
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Filter: \(activeFilterLabel)")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .adaptiveBackground(.subtle, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Selection mode toggle
            Button {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    selectedIDs.removeAll()
                }
            } label: {
                Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelectionMode ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help("Selection Mode")
        }
    }

    // MARK: - Tab List

    private var tabListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(groupedSnapshots, id: \.groupKey) { group in
                    Section {
                        ForEach(group.snapshots) { snapshot in
                            TabHealthRow(
                                snapshot: snapshot,
                                isExpanded: expandedIDs.contains(snapshot.id),
                                isSelected: selectedIDs.contains(snapshot.id),
                                isSelectionMode: isSelectionMode,
                                onTap: {
                                    if isSelectionMode {
                                        toggleSelection(snapshot.id)
                                    } else {
                                        toggleExpanded(snapshot.id)
                                    }
                                },
                                onNavigate: {
                                    navigateToTab(snapshot)
                                },
                                onClose: {
                                    closeTab(snapshot)
                                },
                                onReload: {
                                    reloadTab(snapshot)
                                },
                                onTerminate: {
                                    terminateProcess(snapshot)
                                },
                            )
                        }
                    } header: {
                        sectionHeader(for: group)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DetailTrayEmptyState(
            icon: "light.recessed.3",
            title: "No Tabs",
            message: "Open some tabs to monitor their resource usage",
        )
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if isSelectionMode {
            selectionFooter
        } else {
            actionFooter
        }
    }

    private var actionFooter: some View {
        HStack(spacing: 12) {
            // Suspend inactive
            Button {
                suspendInactiveTabs()
            } label: {
                Label("Unload Inactive", systemImage: "arrow.down.circle")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(LightboardActionButtonStyle())
            .disabled(!healthProvider.hasInactiveTabs)

            // Reload crashed
            if healthProvider.crashedTabCount > 0 {
                Button {
                    reloadCrashedTabs()
                } label: {
                    Label("Reload Crashed", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(LightboardActionButtonStyle(isDestructive: false))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var selectionFooter: some View {
        HStack {
            // Close selected
            Button {
                closeSelectedTabs()
            } label: {
                Label("Close (\(selectedIDs.count))", systemImage: "xmark")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(LightboardActionButtonStyle(isDestructive: true))
            .disabled(selectedIDs.isEmpty)

            Spacer()

            // Done button
            Button {
                isSelectionMode = false
                selectedIDs.removeAll()
            } label: {
                Text("Done")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(LightboardActionButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var activeFilterLabel: String {
        if let processFilter = healthProvider.processFilter {
            let name = healthProvider.availableProcesses.first { $0.pid == processFilter }?.name
            return name ?? "Process"
        }
        return healthProvider.filter.rawValue
    }

    private var groupedSnapshots: [SnapshotGroup] {
        if healthProvider.sortMode == .process {
            let byProcess = Dictionary(grouping: healthProvider.displaySnapshots) { $0.processName.isEmpty ? "Not Running" : $0.processName }
            let result = byProcess.map { key, snapshots in
                let totalMemory = snapshots.first.flatMap { first in
                    first.processName.isEmpty ? nil : first.processMemoryBytes
                } ?? 0
                return SnapshotGroup(
                    groupKey: key,
                    displayName: key,
                    snapshots: snapshots.sorted { $0.id.uuidString < $1.id.uuidString },
                    kind: .process(memoryBytes: totalMemory),
                )
            }
            .sorted { lhs, rhs in
                if case .process(let lhsMem) = lhs.kind, case .process(let rhsMem) = rhs.kind {
                    if lhsMem != rhsMem {
                        return lhsMem > rhsMem
                    }
                }
                return lhs.groupKey < rhs.groupKey
            }
            return result
        } else {
            let bySpace = Dictionary(grouping: healthProvider.displaySnapshots) { $0.spaceName }
            return bySpace.map { SnapshotGroup(groupKey: $0.key, displayName: $0.key, snapshots: $0.value, kind: .space) }
                .sorted { $0.groupKey < $1.groupKey }
        }
    }

    private var memoryInfoPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            memoryInfoRow(
                color: .blue,
                title: "Web",
                description: "Memory used by web page content \u{2014} JavaScript, DOM, images, and media. Each tab runs in its own web process."
            )

            memoryInfoRow(
                color: .green,
                title: "GPU",
                description: "Memory used by WebKit\u{2019}s GPU process for hardware-accelerated rendering, compositing, and video decoding. Shared across all tabs.\n\nNote: GPU texture memory (WebGL, video) is managed by the system and may not be fully reflected here."
            )

            memoryInfoRow(
                color: .orange,
                title: "App",
                description: "Memory used by the Refrax app itself \u{2014} tab management, UI, history, and extensions. Not related to web content."
            )
        }
        .padding(12)
        .frame(width: 260)
    }

    private func memoryInfoRow(color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circlebadge.fill")
                .font(.system(size: 8))
                .foregroundStyle(color)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func graphLegendItem(label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "circlebadge.fill")
                .font(.system(size: 6))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(for group: SnapshotGroup) -> some View {
        HStack {
            if case .process = group.kind {
                processIndicatorDot(for: group.displayName)
            }

            Text(group.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("(\(group.snapshots.count))")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            if case .process(let memoryBytes) = group.kind, memoryBytes > 0 {
                Text("\u{2014} \(memoryBytes / 1_024 / 1_024) MB")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func processIndicatorDot(for processName: String) -> some View {
        let processColors: [Color] = [.blue, .purple, .pink, .orange, .teal, .cyan, .indigo, .mint, .brown, .green]
        let hash = abs(processName.hashValue)
        let color = processColors[hash % processColors.count]
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    // MARK: - Actions

    private func navigateToTab(_ snapshot: TabHealthSnapshot) {
        guard let tab = snapshot.tabPage.tab else { return }
        tabManager.setActiveTab(tab, in: windowState)
    }

    private func closeTab(_ snapshot: TabHealthSnapshot) {
        guard let tab = snapshot.tabPage.tab else { return }
        tabManager.closeTab(tab)
        healthProvider.refresh()
    }

    private func reloadTab(_ snapshot: TabHealthSnapshot) {
        if let webPage = snapshot.webPage {
            webPage.load(snapshot.tabPage.url)
        } else {
            // Tab was unloaded — create a fresh WebPage via page(for:).
            // Don't call load() explicitly — the page's initialLoadPending
            // mechanism handles the first load via performInitialLoadIfNeeded().
            // Calling load() here would race with the deferred initial load,
            // causing it to cancel ours and show "Page loading stopped".
            pagePool.page(for: snapshot.tabPage)
        }
        healthProvider.refresh()
    }

    private func terminateProcess(_ snapshot: TabHealthSnapshot) {
        guard snapshot.processPID > 0 else { return }
        memoryMonitor.unloadProcess(snapshot.processPID)
        healthProvider.refresh()
    }

    private func suspendInactiveTabs() {
        var unloadedPIDs: Set<pid_t> = []
        for snapshot in healthProvider.snapshots where !snapshot.isProtected && !snapshot.isActiveTab {
            if snapshot.processState == .running,
               !snapshot.hasActivityIndicators,
               snapshot.processPID > 0,
               !unloadedPIDs.contains(snapshot.processPID) {
                memoryMonitor.unloadProcess(snapshot.processPID)
                unloadedPIDs.insert(snapshot.processPID)
            }
        }
        healthProvider.refresh()
    }

    private func reloadCrashedTabs() {
        for snapshot in healthProvider.snapshots where snapshot.hasCrashed {
            if let webPage = snapshot.webPage {
                _ = webPage.reload()
            }
        }
        healthProvider.refresh()
    }

    private func closeSelectedTabs() {
        for id in selectedIDs {
            if let snapshot = healthProvider.snapshot(for: id),
               let tab = snapshot.tabPage.tab {
                tabManager.closeTab(tab)
            }
        }
        selectedIDs.removeAll()
        healthProvider.refresh()
    }
}

// MARK: - Supporting Types

private struct SnapshotGroup {
    let groupKey: String
    let displayName: String
    let snapshots: [TabHealthSnapshot]
    let kind: Kind

    enum Kind {
        case space
        case process(memoryBytes: UInt64)
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .adaptiveBackground(.subtle, in: Capsule())
    }
}

// MARK: - Action Button Style

private struct LightboardActionButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isDestructive ? .red : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
