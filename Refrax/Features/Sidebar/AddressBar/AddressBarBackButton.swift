import AppKit
import SwiftUI

/// Back navigation button that manages its own state and actions.
///
/// Takes `canGoBack` as an explicit parameter so SwiftUI can detect when
/// navigation state changes and re-render the button appropriately.
struct AddressBarBackButton: View {
    let webPage: WebPage?
    let canGoBack: Bool

    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager

    @State private var isHovered = false

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                windowState.showDetailTray(.backForward)
            } else {
                webPage?.goBack()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                .foregroundStyle(canGoBack ? (isHovered ? .primary : .secondary) : .quaternary)
                .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canGoBack)
        .onHover { isHovered = $0 }
        .contextMenu { backContextMenu }
        .overlay {
            if canGoBack {
                MiddleClickHandler {
                    if let backItem = webPage?.backList.last {
                        tabManager.createTab(url: backItem.url, makeActive: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var backContextMenu: some View {
        if let backList = webPage?.backList, !backList.isEmpty {
            ForEach(backList) { item in
                Button(item.title ?? item.url.absoluteString) {
                    webPage?.loadBackForwardItem(item)
                }
            }
        }
    }
}

/// Forward navigation button that manages its own state and actions.
///
/// Takes `canGoForward` as an explicit parameter so SwiftUI can detect when
/// navigation state changes and re-render the button appropriately.
struct AddressBarForwardButton: View {
    let webPage: WebPage?
    let canGoForward: Bool

    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager

    @State private var isHovered = false

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                windowState.showDetailTray(.backForward)
            } else {
                webPage?.goForward()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                .foregroundStyle(canGoForward ? (isHovered ? .primary : .secondary) : .quaternary)
                .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canGoForward)
        .onHover { isHovered = $0 }
        .frame(width: canGoForward ? Constants.AddressBar.buttonWidth : 0)
        .opacity(canGoForward ? 1 : 0)
        .clipped()
        .contextMenu { forwardContextMenu }
        .overlay {
            if canGoForward {
                MiddleClickHandler {
                    if let forwardItem = webPage?.forwardList.first {
                        tabManager.createTab(url: forwardItem.url, makeActive: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var forwardContextMenu: some View {
        if let forwardList = webPage?.forwardList, !forwardList.isEmpty {
            ForEach(forwardList) { item in
                Button(item.title ?? item.url.absoluteString) {
                    webPage?.loadBackForwardItem(item)
                }
            }
        }
    }
}

// MARK: - Middle Click Handler

/// Transparent overlay that intercepts middle-clicks.
private struct MiddleClickHandler: NSViewRepresentable {
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

/// AppKit view that intercepts middle-clicks via local event monitor.
private final class MiddleClickView: NSView {
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
        guard event.buttonNumber == 2,
              let window,
              event.window === window else {
            return event
        }

        let locationInWindow = event.locationInWindow
        let locationInSelf = convert(locationInWindow, from: nil)

        guard bounds.contains(locationInSelf) else {
            return event
        }

        action?()
        return nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
