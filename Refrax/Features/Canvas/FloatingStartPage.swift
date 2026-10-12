import SwiftUI

/// The resting page before a tab is opened.
struct FloatingStartPage: View {
    @Environment(WindowState.self) private var windowState
    @Environment(UndoRedoManager.self) private var undoRedo
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @AppStorage("floatingTabs.tutorial.dismissed") private var tutorialDismissed = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Refrax")
                .font(.largeTitle.weight(.medium))
            Button("Command Lens", systemImage: "sparkle.magnifyingglass") { windowState.openCommandLens() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .help("Search pages, tabs, and commands · ⌘T")
            if let recent = undoRedo.recentlyClosedTabs.first(where: { $0.spaceID == windowState.activeSpaceID }) {
                Button {
                    if let index = undoRedo.recentlyClosedTabs.firstIndex(where: { $0.id == recent.id }) {
                        undoRedo.reopenClosedTab(at: index)
                    }
                } label: {
                    Label("Reopen \(recent.customName ?? recent.title)", systemImage: "arrow.uturn.backward")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Reopen the last closed page in this space")
            }
            if !canvas.floatingTabs.isEmpty {
                if let space = windowState.activeSpace,
                   let recent = space.mainTabs.max(by: { ($0.lastAccessed ?? $0.createdAt) < ($1.lastAccessed ?? $1.createdAt) }) {
                    Button("Continue \(space.name)", systemImage: "arrow.right") { tabs.setActiveTab(recent, in: windowState) }
                        .buttonStyle(.plain).help("Resume \(recent.displayTitle)")
                }
                Button("Show open tabs", systemImage: "square.on.square") { canvas.toggleFloatingTabs() }
                    .buttonStyle(.plain)
            }
            if !tutorialDismissed {
                HStack {
                    Button("Try with two pages") { startTutorial() }
                    Button("Dismiss", systemImage: "xmark") { tutorialDismissed = true }
                        .labelStyle(.iconOnly).help("Dismiss tutorial invitation")
                }.buttonStyle(.plain).font(.callout)
            }
            Text("Open something. Put it where you want it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 380)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func startTutorial() {
        guard let space = windowState.activeSpace else { return }
        let draft = tabs.createTab(url: FloatingTabsTutorial.url(reference: false), in: space, makeActive: false)
        let reference = tabs.createTab(url: FloatingTabsTutorial.url(reference: true), in: space, makeActive: false)
        draft.activePage.title = "Trip draft"
        reference.activePage.title = "Arrival details"
        canvas.updateFloatingPlacement(.init(x: 0.1, y: 0.4, isCompact: true, isPinned: false), for: draft)
        canvas.updateFloatingPlacement(.init(x: 0.8, y: 0.4, isCompact: false, isPinned: false), for: reference)
        tabs.setActiveTab(draft, in: windowState)
        canvas.toggleFloatingTabs()
        tutorialDismissed = true
    }

}
