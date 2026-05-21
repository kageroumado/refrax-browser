import AppKit
import SwiftUI

struct AddressBarNavButton<MenuContent: View>: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void
    var optionClickAction: (() -> Void)?
    var middleClickAction: (() -> Void)?
    @ViewBuilder let contextMenu: () -> MenuContent

    @State private var isHovered = false

    var body: some View {
        Button {
            // Check for Option modifier to trigger alternate action
            if NSEvent.modifierFlags.contains(.option), let optionClickAction {
                optionClickAction()
            } else {
                action()
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                .foregroundStyle(isEnabled ? (isHovered ? .primary : .secondary) : .quaternary)
                .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .contextMenu { contextMenu() }
        .overlay {
            if isEnabled, let middleClickAction {
                MiddleClickInterceptor(action: middleClickAction)
            }
        }
    }
}

extension AddressBarNavButton where MenuContent == EmptyView {
    init(
        systemName: String,
        isEnabled: Bool,
        action: @escaping () -> Void,
        optionClickAction: (() -> Void)? = nil,
        middleClickAction: (() -> Void)? = nil,
    ) {
        self.systemName = systemName
        self.isEnabled = isEnabled
        self.action = action
        self.optionClickAction = optionClickAction
        self.middleClickAction = middleClickAction
        self.contextMenu = { EmptyView() }
    }
}

// MARK: - Middle Click Interceptor

/// Intercepts middle-click events and calls the provided action.
private struct MiddleClickInterceptor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context _: Context) -> MiddleClickInterceptorView {
        let view = MiddleClickInterceptorView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MiddleClickInterceptorView, context _: Context) {
        nsView.action = action
    }
}

/// AppKit view that intercepts middle-clicks via local event monitor.
private final class MiddleClickInterceptorView: NSView {
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
        // Middle button is button 2
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
