import AppKit
import SwiftUI

/// The Command Lens's window: clear glass over the whole of the browser window's content, a
/// child of it ordered above every island and card, key while the lens is up so typing lands
/// in the lens, and deaf while it is down so clicks reach what is under it.
final class CommandLensWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Keeps the lens window over the browser window's content, brings it to the front of the
/// children and makes it key when the lens opens, and gives the browser window the keyboard
/// back when it closes. The window stays mounted through the lens's closing animation.
@MainActor
final class CommandLensWindowPresenter {
    private unowned let parent: NSWindow
    private unowned let windowState: WindowState
    private let environment: RefraxEnvironment
    private var window: CommandLensWindow?
    private var observation: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    init(parent: NSWindow, windowState: WindowState, environment: RefraxEnvironment) {
        self.parent = parent
        self.windowState = windowState
        self.environment = environment
    }

    func start() {
        let window = CommandLensWindow()
        let content = FirstMouseHostingView(rootView: CommandLensWindowContent().refraxEnvironment(environment))
        content.sizingOptions = []
        window.contentView = content
        window.setFrame(contentOnScreen, display: false)
        window.ignoresMouseEvents = true
        parent.addChildWindow(window, ordered: .above)
        self.window = window
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow() }
            })
        }
        let windowState = windowState
        let changes = Observations { windowState.showsCommandLens }
        observation = Task(name: "Follow the lens") { [weak self] in
            for await shown in changes {
                self?.lensChanged(shown: shown)
            }
        }
        lensChanged(shown: windowState.showsCommandLens)
    }

    func stop() {
        observation?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        guard let window else { return }
        parent.removeChildWindow(window)
        window.orderOut(nil)
        window.contentView = nil
        self.window = nil
    }

    /// The parent's content area on screen, bottom-up as AppKit has it.
    private var contentOnScreen: CGRect {
        guard let content = parent.contentView else { return parent.frame }
        return parent.convertToScreen(content.frame)
    }

    private func follow() {
        guard let window, window.frame != contentOnScreen else { return }
        window.setFrame(contentOnScreen, display: true)
    }

    private func lensChanged(shown: Bool) {
        guard let window else { return }
        follow()
        if shown {
            // To the front of the children, above islands and cards opened since.
            parent.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
        } else {
            window.ignoresMouseEvents = true
            if window.isKeyWindow {
                parent.makeKey()
            }
        }
    }
}

/// The lens, centered or anchored, in its window: the same overlays, in the same coordinates
/// as the browser window's content, which the window covers exactly.
private struct CommandLensWindowContent: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            CommandLensOverlay()
            AnchoredLensOverlay()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .environment(\.colorScheme, settings.theme.colorScheme ?? colorScheme)
    }
}
