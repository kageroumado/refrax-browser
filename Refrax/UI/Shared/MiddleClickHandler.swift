import AppKit
import SwiftUI

extension View {
    /// Runs `action` on a middle click inside this view's bounds.
    func onMiddleClick(perform action: @escaping () -> Void) -> some View {
        overlay(MiddleClickHandler(action: action))
    }

    /// Closes `tab` on a middle click, as a middle click closes a tab in every browser.
    func closesOnMiddleClick(_ tab: Tab) -> some View {
        modifier(MiddleClickClose(tab: tab))
    }
}

private struct MiddleClickClose: ViewModifier {
    let tab: Tab
    @Environment(TabManager.self) private var tabs

    func body(content: Content) -> some View {
        content.onMiddleClick { tabs.requestCloseTab(tab) }
    }
}

/// Transparent overlay that intercepts middle-clicks.
struct MiddleClickHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context _: Context) -> MiddleClickView {
        let view = MiddleClickView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MiddleClickView, context _: Context) {
        nsView.action = action
    }
}

/// Watches middle-clicks through a local event monitor and lets every other event pass, so
/// the views beneath it keep their clicks.
final class MiddleClickView: NSView {
    var action: (() -> Void)?

    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupEventMonitor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupEventMonitor()
    }

    isolated deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            self?.handleMiddleClick(event) ?? event
        }
    }

    private func handleMiddleClick(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 2, let window, event.window === window,
              bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return event
        }
        action?()
        return nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
