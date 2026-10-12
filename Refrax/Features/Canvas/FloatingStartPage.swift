import SwiftUI

/// The empty page: Command Lens itself, a way back to recent work, and three hints that
/// teach the parts of this browser that nothing else on screen announces.
struct FloatingStartPage: View {
    @Environment(WindowState.self) private var windowState
    @Environment(UndoRedoManager.self) private var undoRedo
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(FloatingTourManager.self) private var tour
    @AppStorage("startPage.hintsDismissed") private var hintsDismissed = false
    @AppStorage("floatingTabs.revealKey") private var revealKey = FloatingRevealKey.control

    private enum Layout {
        static let width: CGFloat = 640
        static let topInset: CGFloat = 150
        static let spacing: CGFloat = 28
        static let hintSpacing: CGFloat = 12
        static let hintPadding: CGFloat = 14
        static let hintCornerRadius: CGFloat = 14
        static let hintFillOpacity: Double = 0.05
    }

    var body: some View {
        VStack(spacing: Layout.spacing) {
            Text("Refrax")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            CommandLensView()
                .id(windowState.startPageLensRequest)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tour.startPageLensFrame = $0 }
            recovery
            if !hintsDismissed { hints }
        }
        .frame(maxWidth: Layout.width)
        .padding(.horizontal, 24)
        .padding(.top, Layout.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { tour.offer() }
        .onDisappear { tour.startPageLensFrame = .zero }
    }

    /// A way back: the last closed page in this space, the last page used here, or the tab layer.
    @ViewBuilder
    private var recovery: some View {
        let recentlyClosed = undoRedo.recentlyClosedTabs.first(where: { $0.spaceID == windowState.activeSpaceID })
        let lastUsed = windowState.activeSpace?.mainTabs.max(by: { ($0.lastAccessed ?? $0.createdAt) < ($1.lastAccessed ?? $1.createdAt) })
        if recentlyClosed != nil || lastUsed != nil {
            HStack(spacing: 20) {
                if let recent = recentlyClosed {
                    Button {
                        if let index = undoRedo.recentlyClosedTabs.firstIndex(where: { $0.id == recent.id }) {
                            undoRedo.reopenClosedTab(at: index)
                        }
                    } label: {
                        Label("Reopen \(recent.customName ?? recent.title)", systemImage: "arrow.uturn.backward").lineLimit(1)
                    }
                    .help("Reopen the last closed page in this space")
                }
                if let lastUsed, let space = windowState.activeSpace {
                    Button {
                        tabs.setActiveTab(lastUsed, in: windowState)
                    } label: {
                        Label("Continue \(space.name)", systemImage: "arrow.right").lineLimit(1)
                    }
                    .help("Resume \(lastUsed.displayTitle)")
                    Button("Show open pages", systemImage: "square.on.square") { canvas.toggleFloatingTabs() }
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var hints: some View {
        VStack(spacing: Layout.hintSpacing) {
            HStack(alignment: .top, spacing: Layout.hintSpacing) {
                hint(symbol: "sparkle.magnifyingglass", title: "Start here",
                     text: "An address, a search, an open page, or a command: type it and press Return. ⌘T brings this back from any page.")
                hint(symbol: "square.on.square", title: "Pages keep their places",
                     text: "Hold \(revealKey.glyph) to see every open page where you put it. Drag a title to move it; pin a page to keep it in view.",
                     action: "Take the tour") { tour.start() }
                hint(symbol: "slider.horizontal.3", title: "Controls that step aside",
                     text: "The panel fades while you work and wakes as you approach. ⌥-drag moves it; More › Customize picks what it holds.",
                     action: "Customize…") { windowState.controlIsland.showsCustomization = true }
            }
            .fixedSize(horizontal: false, vertical: true)
            Button("Got it") { hintsDismissed = true }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hint(symbol: String, title: String, text: String, action: String? = nil, perform: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let perform {
                Button(action, action: perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Layout.hintPadding)
        .background(Color.primary.opacity(Layout.hintFillOpacity), in: .rect(cornerRadius: Layout.hintCornerRadius))
        .accessibilityElement(children: .combine)
    }
}
