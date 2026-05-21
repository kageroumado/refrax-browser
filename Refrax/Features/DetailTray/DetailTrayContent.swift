import AppKit
import SwiftUI

// MARK: - Detail Tray Content

/// SwiftUI content for the AppKit-animated detail tray panel.
///
/// This view hosts the content for the detail tray, switching between
/// downloads, bookmarks, and history based on `windowState.detailTrayMode`.
/// The glass effect container and animations are handled by AppKit in
/// `RefraxWindowController+DetailTray.swift`.
///
/// Design follows Apple Maps' secondary panel pattern:
/// - Large title with close button in header
/// - Scrollable content area
/// - Bottom toolbar with contextual actions
struct DetailTrayContent: View {
    @Environment(WindowState.self) private var windowState

    private enum Constants {
        static let headerPadding: CGFloat = 16
        static let headerTopPadding: CGFloat = 12
        static let titleFontSize: CGFloat = 22
    }

    var body: some View {
        VStack(spacing: 0) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Refrax.Constants.DetailTray.width)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(edges: .vertical)
        .onExitCommand {
            windowState.hideDetailTray()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch windowState.detailTrayMode {
        case .downloads:
            DownloadsTrayView()
        case .bookmarks:
            BookmarksTrayView()
        case .history:
            HistoryTrayView()
        case .backForward:
            BackForwardTrayView()
        case .tabSnapshots:
            SnapshotBrowserView()
        case .lightboard:
            LightboardView()
        case .hidden:
            EmptyView()
        }
    }
}

// MARK: - Detail Tray Header

/// Header bar for the detail tray matching toolbar button styling.
///
/// Design matches NSToolbarButton appearance:
/// - Title inline with buttons (like Settings "Bluetooth")
/// - Buttons have no background, primary color, capsule hover
/// - Tight spacing matching toolbar dimensions
struct DetailTrayHeader: View {
    @Environment(WindowState.self) private var windowState

    let title: String
    let currentMode: DetailTrayMode
    var onBack: (() -> Void)?
    var onExpand: (() -> Void)?
    let onClose: () -> Void

    private enum Constants {
        static let horizontalPadding: CGFloat = 5 // Match toolbar button inset from edge
        static let topPadding: CGFloat = 6
        static let bottomPadding: CGFloat = 14
        /// Toolbar buttons are in 44pt cells, button is 33.5pt, so 10.5pt gap between edges
        static let buttonSpacing: CGFloat = 10.5
    }

    var body: some View {
        HStack(alignment: .center, spacing: Constants.buttonSpacing) {
            // Back button (only shown when there's somewhere to go back to)
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(DetailTrayHeaderButtonStyle())
                .help("Back")
            }

            // Title with dropdown menu (SwiftUI label + AppKit NSMenu overlay)
            DetailTrayTitleLabel(title: title, isCompact: onBack != nil)
                .padding(.leading, onBack == nil ? 12 : 0)
                .overlay {
                    DetailTrayTitleMenuOverlay(
                        currentMode: currentMode,
                        onSelectMode: { windowState.showDetailTray($0) },
                    )
                }

            Spacer()

            HStack(spacing: Constants.buttonSpacing) {
                if let onExpand {
                    Button(action: onExpand) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(DetailTrayHeaderButtonStyle())
                    .help("Open in Window")
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(DetailTrayHeaderButtonStyle())
                .help("Close")
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
        .zIndex(1)
    }
}

// MARK: - Detail Tray Title Menu

/// SwiftUI title label with chevron for the detail tray header.
private struct DetailTrayTitleLabel: View {
    let title: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: isCompact ? 16 : 19, weight: isCompact ? .semibold : .semibold))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: isCompact ? 8 : 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }
}

/// Invisible overlay that shows an NSMenu on click.
///
/// Uses NSMenu instead of SwiftUI Menu for better control, consistent appearance,
/// and proper focus behavior. The title is rendered by SwiftUI; this overlay only
/// handles the click and menu presentation.
private struct DetailTrayTitleMenuOverlay: NSViewRepresentable {
    let currentMode: DetailTrayMode
    let onSelectMode: (DetailTrayMode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectMode: onSelectMode)
    }

    func makeNSView(context: Context) -> DetailTrayTitleMenuOverlayView {
        let view = DetailTrayTitleMenuOverlayView()
        view.currentMode = currentMode
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DetailTrayTitleMenuOverlayView, context: Context) {
        nsView.currentMode = currentMode
        nsView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject {
        let onSelectMode: (DetailTrayMode) -> Void

        init(onSelectMode: @escaping (DetailTrayMode) -> Void) {
            self.onSelectMode = onSelectMode
        }

        /// AppKit callbacks must dispatch SwiftUI state changes asynchronously
        /// to avoid "modifying state during view update" issues and infinite loops.
        @objc
        func selectHistory(_: NSMenuItem) {
            DispatchQueue.main.async { [self] in onSelectMode(.history) }
        }

        @objc
        func selectDownloads(_: NSMenuItem) {
            DispatchQueue.main.async { [self] in onSelectMode(.downloads) }
        }

        @objc
        func selectBookmarks(_: NSMenuItem) {
            DispatchQueue.main.async { [self] in onSelectMode(.bookmarks) }
        }

        @objc
        func selectTabSnapshots(_: NSMenuItem) {
            DispatchQueue.main.async { [self] in onSelectMode(.tabSnapshots) }
        }

        @objc
        func selectLightboard(_: NSMenuItem) {
            DispatchQueue.main.async { [self] in onSelectMode(.lightboard) }
        }
    }
}

/// Transparent NSView that shows a popup menu on click.
private final class DetailTrayTitleMenuOverlayView: NSView {
    var currentMode: DetailTrayMode = .bookmarks
    weak var coordinator: DetailTrayTitleMenuOverlay.Coordinator?

    override func mouseDown(with _: NSEvent) {
        guard let coordinator else { return }

        let menu = NSMenu()

        let modes: [DetailTrayMode] = [.history, .downloads, .bookmarks, .tabSnapshots, .lightboard]
        for mode in modes where mode != currentMode {
            let item = NSMenuItem(
                title: mode.title,
                action: selector(for: mode),
                keyEquivalent: "",
            )
            item.target = coordinator
            item.image = NSImage(systemSymbolName: mode.icon, accessibilityDescription: nil)
            menu.addItem(item)
        }

        // Position menu below the title, trailing-aligned
        let menuSize = menu.size
        let point = NSPoint(x: bounds.width - menuSize.width, y: -4)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    private func selector(for mode: DetailTrayMode) -> Selector {
        switch mode {
        case .history: #selector(DetailTrayTitleMenuOverlay.Coordinator.selectHistory(_:))
        case .downloads: #selector(DetailTrayTitleMenuOverlay.Coordinator.selectDownloads(_:))
        case .bookmarks: #selector(DetailTrayTitleMenuOverlay.Coordinator.selectBookmarks(_:))
        case .tabSnapshots: #selector(DetailTrayTitleMenuOverlay.Coordinator.selectTabSnapshots(_:))
        case .lightboard: #selector(DetailTrayTitleMenuOverlay.Coordinator.selectLightboard(_:))
        case .hidden, .backForward: #selector(DetailTrayTitleMenuOverlay.Coordinator.selectHistory(_:))
        }
    }
}

/// Button style matching NSToolbarButton: squished oval hover (33.5×24).
private struct DetailTrayHeaderButtonStyle: ButtonStyle {
    @State private var isHovered = false

    /// Width matches toolbar, height is squished for the hover oval.
    private enum Constants {
        static let width: CGFloat = 33.5
        static let height: CGFloat = 24
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: Constants.width, height: Constants.height)
            .background {
                if isHovered || configuration.isPressed {
                    Capsule()
                        .fill(.quaternary)
                }
            }
            .contentShape(Capsule())
            .onHover { isHovered = $0 }
    }
}

// MARK: - DetailTrayMode Extensions

extension DetailTrayMode {
    /// Display title for the mode.
    var title: String {
        switch self {
        case .hidden: ""
        case .downloads: "Downloads"
        case .bookmarks: "Bookmarks"
        case .history: "History"
        case .backForward: "Navigation"
        case .tabSnapshots: "Tab Snapshots"
        case .lightboard: "Lightboard"
        }
    }

    /// SF Symbol icon for the mode.
    var icon: String {
        switch self {
        case .hidden: ""
        case .downloads: "arrow.down.circle"
        case .bookmarks: "bookmark"
        case .history: "clock"
        case .backForward: "arrow.left.arrow.right"
        case .tabSnapshots: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .lightboard: "light.recessed.3"
        }
    }
}

// MARK: - Detail Tray Toolbar Constants

private enum DetailTrayToolbarConstants {
    static let buttonSize: CGFloat = 32
    static let iconSize: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 16
    static let toolbarCornerRadius: CGFloat = 16
    static let toolbarHorizontalPadding: CGFloat = 0
    static let toolbarVerticalPadding: CGFloat = 0
    static let toolbarBottomPadding: CGFloat = 8
}

// MARK: - Detail Tray Toolbar (Normal Mode)

/// Capsule-shaped toolbar for the detail tray's normal mode buttons.
///
/// Places buttons inside a shared capsule container, centered at the bottom.
/// Uses the same sizing as SidebarControlButton (32pt buttons, 12pt icons).
struct DetailTrayToolbar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.horizontal, DetailTrayToolbarConstants.toolbarHorizontalPadding)
        .padding(.vertical, DetailTrayToolbarConstants.toolbarVerticalPadding)
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: DetailTrayToolbarConstants.toolbarCornerRadius))
        .padding(.bottom, DetailTrayToolbarConstants.toolbarBottomPadding)
    }
}

/// A button for use inside DetailTrayToolbar (capsule style).
///
/// Uses same sizing as SidebarControlButton but without individual background or hover effect.
struct DetailTrayToolbarButton: View {
    let icon: String
    let action: () -> Void
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    var help: String?

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: DetailTrayToolbarConstants.iconSize, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: DetailTrayToolbarConstants.buttonSize, height: DetailTrayToolbarConstants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help ?? "")
    }

    private var foregroundColor: Color {
        if isDisabled {
            .secondary.opacity(0.5)
        } else if isDestructive {
            .red
        } else {
            .primary
        }
    }
}

// MARK: - Detail Tray Circle Button (Edit Mode)

/// Circular button for the detail tray's edit/selection mode.
///
/// Uses the same sizing as SidebarControlButton without hover effect.
struct DetailTrayCircleButton: View {
    let icon: String
    let action: () -> Void
    var isDestructive: Bool = false
    var isActive: Bool = false
    var isDisabled: Bool = false
    var help: String?

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: DetailTrayToolbarConstants.iconSize, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: DetailTrayToolbarConstants.buttonSize, height: DetailTrayToolbarConstants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help ?? "")
    }

    private var foregroundColor: Color {
        if isDisabled {
            .secondary.opacity(0.5)
        } else if isDestructive {
            .red
        } else if isActive {
            .appAccentColor
        } else {
            .primary
        }
    }
}

// MARK: - Detail Tray Selection Footer Button

/// Circular button for the detail tray's selection mode footer.
///
/// Supports two visual styles:
/// - Inactive (disabled): Icon color with adaptive background
/// - Active (enabled): White icon with colored background
struct DetailTraySelectionButton: View {
    let icon: String
    let action: () -> Void
    let color: Color
    var isActive: Bool = true
    var help: String?

    private enum Constants {
        static let buttonSize: CGFloat = 32
        static let buttonCornerRadius: CGFloat = 16
        static let iconSize: CGFloat = 12
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(isActive ? .white : color)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background {
                    if isActive {
                        Circle().fill(color)
                    } else {
                        Circle().fill(.clear)
                            .adaptiveBackground(.subtle, in: Circle())
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
        .help(help ?? "")
    }
}

// MARK: - Detail Tray Selection Footer

/// Footer for selection mode with buttons positioned at edges.
struct DetailTraySelectionFooter: View {
    let deleteAction: () -> Void
    let doneAction: () -> Void
    var hasSelection: Bool

    var body: some View {
        HStack {
            DetailTraySelectionButton(
                icon: "trash",
                action: deleteAction,
                color: .red,
                isActive: hasSelection,
                help: "Delete Selected",
            )

            Spacer()

            DetailTraySelectionButton(
                icon: "checkmark",
                action: doneAction,
                color: .blue,
                help: "Done",
            )
        }
        .padding(.horizontal, 8)
        .padding(.bottom, DetailTrayToolbarConstants.toolbarBottomPadding)
    }
}

// MARK: - Detail Tray Footer Container

/// Container for the detail tray footer area.
///
/// Provides centered layout for toolbar contents without background.
struct DetailTrayFooter<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Spacer()
            content
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Detail Tray Search Field

/// Shared search field for detail tray headers.
struct DetailTraySearchField: View {
    @Binding var text: String
    let placeholder: String

    private enum Constants {
        static let cornerRadius: CGFloat = 16
    }

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Constants.cornerRadius))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

// MARK: - Detail Tray Section Header

/// Pinned section header with adaptive capsule background.
///
/// The background only appears when content has scrolled behind the header,
/// fading in progressively. Uses `.adaptiveBackground` which adapts to the
/// colors underneath rather than a static material.
///
/// Design principles:
/// - Capsule hugs the text (Liquid Glass: take only needed space)
/// - Background appears progressively as content scrolls behind
/// - Uses adaptive background for adaptive coloring
struct DetailTraySectionHeader: View {
    let title: String
    let scrollOffset: CGFloat

    private enum Constants {
        static let capsuleHPadding: CGFloat = 10
        static let capsuleVPadding: CGFloat = 5
        static let capsuleCornerRadius: CGFloat = 12
        static let maxUpwardOffset: CGFloat = 12
    }

    /// Upward offset with 1:1 relationship to scroll, clamped to max.
    /// Scroll 10px → header moves 10px up. Scroll 20px → capped at 12px.
    private var upwardOffset: CGFloat {
        guard scrollOffset > 0 else { return 0 }
        return -min(scrollOffset, Constants.maxUpwardOffset)
    }

    /// Background opacity that fades in as header reaches max offset.
    private var backgroundOpacity: Double {
        guard scrollOffset > 0 else { return 0 }
        return min(1, scrollOffset / Constants.maxUpwardOffset)
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Constants.capsuleHPadding)
                .padding(.vertical, Constants.capsuleVPadding)
                .background {
                    Capsule()
                        .fill(.clear)
                        .adaptiveBackground(.subtle, in: Capsule())
                        .opacity(backgroundOpacity)
                }
                .offset(y: upwardOffset)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - Detail Tray Empty State

/// Empty state view for when there's no content.
struct DetailTrayEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
