import SwiftUI

/// A guide overlay shown in the main content area when no tab is active.
///
/// Displays hint bubbles vertically distributed to align with their corresponding
/// sidebar elements, with a staggered horizontal layout for visual rhythm.
/// A keyboard shortcuts reference appears on the right side. Each bubble uses
/// `.glassEffect()` for visual treatment.
///
/// Dismissed via the "Don't show again" button, which sets `BrowserSettings.showSidebarHints`
/// to false. Can be re-enabled from Settings > General.
struct SidebarHintsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(GuidedTourManager.self) private var tourManager

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let width = geometry.size.width
            let leftX = Constants.bubbleMaxWidth / 2 + Constants.horizontalPadding

            // Top cluster: toolbar, address bar — left-aligned
            VStack(alignment: .leading, spacing: 0) {
                hintBubble(
                    icons: ["sidebar.left", "rectangle.split.2x1", "sidebar.right"],
                    title: "Toolbar",
                    description: "Toggle sidebar visibility (\(Text("⌘S").bold())), enable split view for side-by-side browsing, or show the reference pane for pinned pages and AI chat. The sidebar has three modes: default, compact, and overlay — configurable in settings."
                )
                .padding(.bottom, Constants.clusterGap)

                hintBubble(
                    icons: ["chevron.left", "chevron.right", "arrow.clockwise"],
                    title: "Address Bar",
                    description: "Navigate with back/forward buttons. Hold \(Text("⌥").bold()) for the history tray, or right-click for a quick list. Right-click reload to bypass cache. The page menu configures per-site settings."
                )
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .position(x: leftX, y: height * 0.17)

            // Command Lens — center area with action buttons below
            VStack(spacing: Constants.dismissGap) {
                hintBubble(
                    icons: ["sparkle.magnifyingglass"],
                    title: "Command Lens",
                    description: "Your unified control center. Press \(Text("⌘T").bold()) to open tabs, search history and bookmarks, change settings, find open tabs, or talk to AI."
                )

                actionButtons
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .position(x: leftX + Constants.staggerOffset, y: height * 0.42)

            // Tabs — left-aligned
            hintBubble(
                icons: ["star", "pin", "folder"],
                title: "Tabs",
                description: "Favorite tabs to keep them always visible. Pin tabs to the top. Drag to reorder, or drag between pinned and favorites. Hold \(Text("⌥").bold()) and click the new tab button to create a group."
            )
            .padding(.horizontal, Constants.horizontalPadding)
            .position(x: leftX, y: height * 0.65)

            // Spaces — bottom left
            hintBubble(
                icons: ["globe", "line.3.horizontal.decrease", "square.on.square"],
                title: "Spaces & Controls",
                description: "Switch between spaces to separate work and personal browsing. Spaces can be locked with Touch ID and made private with separate browsing contexts. Filter tabs by name or URL."
            )
            .padding(.horizontal, Constants.horizontalPadding)
            .position(x: leftX + Constants.staggerOffset, y: height * 0.82)

            // Keyboard shortcuts — right side, vertically centered
            if width > Constants.shortcutsMinWindowWidth {
                shortcutsBubble
                    .position(
                        x: width - Constants.shortcutsWidth / 2 - Constants.horizontalPadding,
                        y: height * 0.45
                    )
            }
        }
    }

    // MARK: - Hint Bubble

    private func hintBubble(
        icons: [String],
        title: String,
        description: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: Constants.bubbleContentSpacing) {
            iconVignette(icons)

            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Constants.bubblePadding)
        .frame(maxWidth: Constants.bubbleMaxWidth, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Constants.bubbleCornerRadius))
    }

    // MARK: - Icon Vignette

    private func iconVignette(_ names: [String]) -> some View {
        HStack(spacing: Constants.iconSpacing) {
            ForEach(names, id: \.self) { name in
                Image(systemName: name)
                    .font(.system(size: Constants.iconSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    private var shortcutsBubble: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
                .font(.headline)

            shortcutsGrid
        }
        .padding(Constants.bubblePadding)
        .frame(width: Constants.shortcutsWidth, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Constants.bubbleCornerRadius))
    }

    private var shortcutsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            sectionHeader("Essentials")
            shortcutEntry("⌘T", "Command Lens")
            shortcutEntry("⌘S", "Toggle Sidebar")
            shortcutEntry("⌘W", "Close Tab")
            shortcutEntry("⌘⇧T", "Reopen Closed Tab")
            shortcutEntry("⌘L", "Focus Address Bar")

            sectionHeader("Navigation")
            shortcutEntry("⌘[  ⌘]", "Back / Forward")
            shortcutEntry("⌘R", "Reload")
            shortcutEntry("⌘⇧R", "Reload (No Cache)")
            shortcutEntry("⌘⌥↑  ⌘⌥↓", "Prev / Next Tab")

            sectionHeader("Features")
            shortcutEntry("⌘D", "Bookmark Page")
            shortcutEntry("⌘F", "Find in Page")
            shortcutEntry("⌘⌃T", "Split View")
            shortcutEntry("⌘⌃S", "Reference Pane")
            shortcutEntry("⌘⌥I", "Web Inspector")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        GridRow {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .gridCellColumns(2)
        }
    }

    private func shortcutEntry(_ keys: String, _ action: String) -> some View {
        GridRow {
            Text(keys)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.primary)

            Text(action)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                tourManager.start()
            } label: {
                Label("Take a Tour", systemImage: "play.circle")
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(.white.opacity(0.15)), in: .capsule)

            Button("Don't show again") {
                settings.showSidebarHints = false
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
        .frame(maxWidth: Constants.bubbleMaxWidth, alignment: .center)
    }
}

// MARK: - Constants

private extension SidebarHintsView {
    enum Constants {
        static let horizontalPadding: CGFloat = 32
        static let clusterGap: CGFloat = 12
        static let dismissGap: CGFloat = 16
        static let staggerOffset: CGFloat = 40
        static let bubblePadding: CGFloat = 16
        static let bubbleMaxWidth: CGFloat = 380
        static let bubbleCornerRadius: CGFloat = 16
        static let bubbleContentSpacing: CGFloat = 8
        static let iconSize: CGFloat = 18
        static let iconSpacing: CGFloat = 10
        static let shortcutsWidth: CGFloat = 340
        static let shortcutsMinWindowWidth: CGFloat = 900
    }
}
