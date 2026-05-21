import AppKit
import SwiftUI

// MARK: - Tab Health Row

/// A row displaying a single tab's health status in the Lightboard dashboard.
///
/// Shows:
/// - Process state indicator (colored dot)
/// - Favicon and title
/// - Memory usage
/// - Activity badges (audio, camera, mic, form)
/// - Expandable detail section with process info and memory
struct TabHealthRow: View {
    let snapshot: TabHealthSnapshot
    let isExpanded: Bool
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let onNavigate: () -> Void
    let onClose: () -> Void
    let onReload: () -> Void
    let onTerminate: () -> Void

    @State private var isHovered = false

    private enum Constants {
        static let iconSize: CGFloat = 24
        static let stateIndicatorSize: CGFloat = 8
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 10
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row — uses Button instead of onTapGesture to avoid
            // double-fire when SwiftUI recreates views during memory updates
            Button {
                onTap()
            } label: {
                mainRow
                    .padding(.horizontal, Constants.horizontalPadding)
                    .padding(.vertical, Constants.verticalPadding)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.blue.opacity(0.15))
                        } else if isHovered {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .contextMenu { contextMenu }

            // Expanded detail
            if isExpanded {
                expandedDetail
                    .padding(.horizontal, Constants.horizontalPadding)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 10) {
            // Selection checkbox or state indicator
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .blue : .secondary)
            } else {
                // State indicator
                Circle()
                    .fill(snapshot.processState.color)
                    .frame(width: Constants.stateIndicatorSize, height: Constants.stateIndicatorSize)
            }

            // Favicon
            faviconView

            // Title and domain
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(snapshot.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    // Activity badges
                    activityBadges
                }

                Text(snapshot.domain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Memory usage
            memoryBadge

            // Expand chevron (if not in selection mode)
            if !isSelectionMode {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Favicon

    @ViewBuilder
    private var faviconView: some View {
        if let faviconData = snapshot.tabPage.faviconData,
           let faviconImage = NSImage(data: faviconData) {
            Image(nsImage: faviconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            // Fallback: domain-based icon
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(domainColor.opacity(0.15))

                Text(String(snapshot.domain.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(domainColor)
            }
            .frame(width: Constants.iconSize, height: Constants.iconSize)
        }
    }

    // MARK: - Activity Badges

    @ViewBuilder
    private var activityBadges: some View {
        HStack(spacing: 2) {
            if snapshot.isPlayingAudio {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue)
            }

            if snapshot.cameraCaptureState == .active {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
            }

            if snapshot.microphoneCaptureState == .active {
                Image(systemName: "mic.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }

            if snapshot.hasUnsavedFormData {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)
            }

            if snapshot.hasCrashed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Memory Badge

    private var memoryBadge: some View {
        HStack(spacing: 3) {
            if snapshot.sharesProcess {
                Circle()
                    .fill(processIndicatorColor)
                    .frame(width: 6, height: 6)
            }
            Text(snapshot.formattedMemory)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(memoryColor)
    }

    private var memoryColor: Color {
        if snapshot.processState == .notRunning || snapshot.processState == .suspended {
            return .secondary
        }
        let mb = snapshot.estimatedTabMemoryBytes / 1_024 / 1_024
        if mb > 1000 { return .red }
        if mb > 500 { return .orange }
        return .secondary
    }

    /// Color for the process sharing indicator dot.
    /// Uses a stable color derived from the process name to ensure
    /// tabs in the same process get the same color.
    private var processIndicatorColor: Color {
        let processColors: [Color] = [.blue, .purple, .pink, .orange, .teal, .cyan, .indigo, .mint, .brown, .green]
        let hash = abs(snapshot.processName.hashValue)
        return processColors[hash % processColors.count]
    }

    // MARK: - Expanded Detail

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            // Process info
            VStack(alignment: .leading, spacing: 4) {
                Text("Process")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack {
                    Image(systemName: snapshot.processState.icon)
                        .foregroundStyle(snapshot.processState.color)
                        .frame(width: 16)

                    Text(snapshot.processState.rawValue)
                        .font(.system(size: 12))

                    if snapshot.processPID > 0 {
                        if snapshot.sharesProcess {
                            Circle()
                                .fill(processIndicatorColor)
                                .frame(width: 6, height: 6)
                        }

                        Text("\(snapshot.processName) (PID \(snapshot.processPID))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    if let reason = snapshot.lastTerminationReason {
                        Text("(\(reason.logDescription))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Memory details
            if snapshot.processMemoryBytes > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack {
                        Text("Process: \(snapshot.formattedProcessMemory)")
                            .font(.system(size: 12))

                        if snapshot.sharesProcess {
                            Text("Est. tab: \(snapshot.formattedMemory)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Importance factors
            if !snapshot.importanceFactors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Importance (\(snapshot.importanceScore))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(snapshot.importanceFactors) { factor in
                        HStack {
                            Image(systemName: factor.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Text(factor.name)
                                .font(.system(size: 12))

                            Spacer()

                            Text("+\(factor.points)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Timestamps
            VStack(alignment: .leading, spacing: 4) {
                if let lastVisible = snapshot.lastVisibleAt {
                    HStack {
                        Text("Last Viewed:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(relativeDate(lastVisible))
                            .font(.system(size: 11))
                    }
                }

                HStack {
                    Text("Created:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(relativeDate(snapshot.createdAt))
                        .font(.system(size: 11))
                }
            }

            // Action buttons — icons on left, actions on right
            HStack(spacing: 6) {
                if !snapshot.isActiveTab {
                    Button { onNavigate() } label: {
                        Image(systemName: "arrow.right.circle")
                    }
                    .buttonStyle(TabHealthActionButtonStyle())
                    .help("Go to Tab")
                }

                Button { onClose() } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(TabHealthActionButtonStyle(isDestructive: true))
                .help("Close Tab")

                Spacer()

                if snapshot.processState == .notRunning || snapshot.hasCrashed {
                    Button("Reload") { onReload() }
                        .buttonStyle(TabHealthActionButtonStyle())
                }

                if !snapshot.isActiveTab, snapshot.processState == .running || snapshot.processState == .background {
                    Button(snapshot.tabsInProcess > 1 ? "Unload (\(snapshot.tabsInProcess))" : "Unload") { onTerminate() }
                        .buttonStyle(TabHealthActionButtonStyle(isDestructive: true))
                        .help("Remove from memory. Tab reloads when opened.")
                }
            }
        }
        .padding(.leading, Constants.stateIndicatorSize + 10)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenu: some View {
        if !snapshot.isActiveTab {
            Button("Go to Tab") { onNavigate() }
        }

        if snapshot.processState == .notRunning || snapshot.hasCrashed {
            Button("Reload Tab") { onReload() }
        }

        Divider()

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(snapshot.url.absoluteString, forType: .string)
        }

        if !snapshot.isActiveTab, snapshot.processState == .running || snapshot.processState == .background {
            Button("Unload Tab", role: .destructive) { onTerminate() }
        }

        Divider()

        Button("Close Tab", role: .destructive) { onClose() }
    }

    // MARK: - Helpers

    private var domainColor: Color {
        let hash = snapshot.domain.hashValue
        let colors: [Color] = [.blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo]
        return colors[abs(hash) % colors.count]
    }

    private func relativeDate(_ date: Date) -> String {
        date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}

// MARK: - Tab Health Action Button Style

private struct TabHealthActionButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.clear)
                    .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 6))
            }
            .foregroundStyle(isDestructive ? .red : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
