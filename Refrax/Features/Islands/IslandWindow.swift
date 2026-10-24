import AppKit
import SwiftUI

/// An island as a window of its own over the page: borderless glass, a child of the browser
/// window, moved by dragging any of its empty glass. Its hover, its drags and its menus are
/// its own, whatever the page under it does.
final class IslandWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Keeps one window per island on screen, where the island's frame says, and writes a window
/// the person drags back into the island's placement.
@MainActor
final class IslandWindowPresenter {
    private struct Entry {
        let window: IslandWindow
        var observers: [any NSObjectProtocol] = []
        var settle: Task<Void, Never>?
    }

    private struct Key: Equatable {
        var frames: [UUID: CGRect]
        var hidden: Bool
        var dragged: UUID?
    }

    private enum Layout {
        static let fade: TimeInterval = 0.18
        static let releasePoll: Duration = .milliseconds(50)
    }

    private unowned let parent: NSWindow
    private unowned let windowState: WindowState
    private unowned let islands: IslandController
    private let environment: RefraxEnvironment
    private var entries: [UUID: Entry] = [:]
    private var observation: Task<Void, Never>?

    init(parent: NSWindow, windowState: WindowState, islands: IslandController, environment: RefraxEnvironment) {
        self.parent = parent
        self.windowState = windowState
        self.islands = islands
        self.environment = environment
    }

    func start() {
        sync()
        let islands = islands
        let windowState = windowState
        let changes = Observations {
            Key(
                frames: Dictionary(uniqueKeysWithValues: islands.visibleIslands.map { ($0.id, islands.frame(of: $0)) }),
                hidden: windowState.showsCommandLens || windowState.isSpaceLocked,
                dragged: islands.draggedIslandID,
            )
        }
        observation = Task(name: "Follow the islands") { [weak self] in
            for await _ in changes {
                self?.sync()
            }
        }
    }

    func stop() {
        observation?.cancel()
        for id in Array(entries.keys) {
            close(id, animated: false)
        }
    }

    // MARK: - Keeping the windows in step

    private func sync() {
        let visible = islands.visibleIslands
        let hidden = windowState.showsCommandLens || windowState.isSpaceLocked
        for id in Array(entries.keys) where !visible.contains(where: { $0.id == id }) {
            close(id, animated: true)
        }
        for island in visible {
            let entry = entries[island.id] ?? open(island)
            if islands.draggedIslandID != island.id {
                let target = screenFrame(for: islands.frame(of: island))
                if entry.window.frame != target {
                    entry.window.setFrame(target, display: true)
                }
            }
            entry.window.ignoresMouseEvents = hidden
            fade(entry.window, to: hidden ? 0 : 1)
        }
    }

    private func open(_ island: Island) -> Entry {
        let window = IslandWindow()
        let controller = NSHostingController(rootView: IslandWindowContent(islandID: island.id).refraxEnvironment(environment))
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setFrame(screenFrame(for: islands.frame(of: island)), display: false)
        window.alphaValue = 0
        var entry = Entry(window: window)
        let id = island.id
        entry.observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowMoved(id) }
        })
        entries[id] = entry
        islands.islandWindows[id] = window
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        return entry
    }

    private func close(_ id: UUID, animated: Bool) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.settle?.cancel()
        for observer in entry.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        islands.islandWindows[id] = nil
        let window = entry.window
        let parent = parent
        let finish = { @MainActor in
            parent.removeChildWindow(window)
            window.orderOut(nil)
            window.contentViewController = nil
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Layout.fade
                window.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated(finish) })
        } else {
            finish()
        }
    }

    private func fade(_ window: NSWindow, to alpha: CGFloat) {
        guard window.alphaValue != alpha else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.fade
            window.animator().alphaValue = alpha
        }
    }

    // MARK: - Geometry

    /// The parent's content area on screen, bottom-up as AppKit has it.
    private var contentOnScreen: CGRect {
        guard let content = parent.contentView else { return parent.frame }
        return parent.convertToScreen(content.frame)
    }

    /// An island's frame, top-down in the parent's content, on screen.
    private func screenFrame(for frame: CGRect) -> CGRect {
        let content = contentOnScreen
        return CGRect(x: content.minX + frame.minX, y: content.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    /// The person is dragging the window: the island's placement follows it, and once the
    /// window is let go the move is kept and the island settles inside the area.
    private func windowMoved(_ id: UUID) {
        guard var entry = entries[id], NSEvent.pressedMouseButtons != 0 || islands.draggedIslandID == id else { return }
        let content = contentOnScreen
        let screen = entry.window.frame
        islands.draggedIslandID = id
        islands.moveIsland(id, to: CGPoint(x: screen.minX - content.minX, y: content.maxY - screen.maxY))
        entry.window.orderFront(nil)
        entry.settle?.cancel()
        entry.settle = Task(name: "Settle an island") { [weak self] in
            while NSEvent.pressedMouseButtons != 0, !Task.isCancelled {
                try? await Task.sleep(for: Layout.releasePoll)
            }
            guard !Task.isCancelled, let self else { return }
            islands.draggedIslandID = nil
            islands.endIslandMove(keeping: id)
            sync()
        }
        entries[id] = entry
    }
}

/// The window's content: the island as it is now, looked up by id so a rebuilt island is
/// drawn afresh.
private struct IslandWindowContent: View {
    let islandID: UUID

    @Environment(IslandController.self) private var islands
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let island = islands.island(islandID) {
            IslandView(island: island)
                .coordinateSpace(name: "island")
                .environment(\.colorScheme, settings.theme.colorScheme ?? colorScheme)
        }
    }
}
