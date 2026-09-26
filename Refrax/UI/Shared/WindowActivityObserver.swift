import AppKit

/// Reports whether a view's window is the active app's key window.
///
/// This is the state `NSVisualEffectView.followsWindowActiveState` and Liquid Glass
/// follow: the system stops sampling behind its materials the moment the window is no
/// longer key, so an inactive window costs WindowServer nothing per frame. A custom
/// `CABackdropLayer` keeps sampling on every frame of the display until its owner
/// stops it, which is what `onChange` is for.
///
/// Owned by the view; call ``observe(_:)`` from `viewDidMoveToWindow()`.
@MainActor
final class WindowActivityObserver {
    private let onChange: (_ isActive: Bool) -> Void
    private var tokens: [any NSObjectProtocol] = []
    private weak var window: NSWindow?

    init(onChange: @escaping (_ isActive: Bool) -> Void) {
        self.onChange = onChange
    }

    isolated deinit {
        removeTokens()
    }

    /// Follows `window`, or stops following when it is nil. Reports the current state
    /// immediately.
    func observe(_ window: NSWindow?) {
        removeTokens()
        self.window = window
        guard let window else { return }

        let center = NotificationCenter.default
        let names: [(Notification.Name, AnyObject?)] = [
            (NSWindow.didBecomeKeyNotification, window),
            (NSWindow.didResignKeyNotification, window),
            (NSApplication.didBecomeActiveNotification, nil),
            (NSApplication.didResignActiveNotification, nil),
        ]
        for (name, object) in names {
            let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.report()
                }
            }
            tokens.append(token)
        }
        report()
    }

    private func report() {
        guard let window else { return }
        onChange(NSApplication.shared.isActive && window.isKeyWindow)
    }

    private func removeTokens() {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
    }
}
