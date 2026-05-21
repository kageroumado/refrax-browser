import AppKit
import SwiftUI
import WebKit

// MARK: - Extension Popup State

/// Represents an extension popup to display.
struct ExtensionPopupRequest: Identifiable {
    let id = UUID()
    let extensionName: String
    let extensionIcon: NSImage?
    let popupWebView: WKWebView
    let continuation: CheckedContinuation<Void, any Error>
}

/// Manages extension popup presentation using a floating panel.
@Observable
final class ExtensionPopupManager {
    /// The current popup request to display, if any.
    private(set) var currentPopup: ExtensionPopupRequest?

    /// The floating panel for popup display.
    private var popupPanel: ExtensionPopupPanel?

    /// Queue of pending popup requests.
    private var popupQueue: [ExtensionPopupRequest] = []

    /// Enqueues a popup request.
    func enqueue(_ request: ExtensionPopupRequest) {
        popupQueue.append(request)
        showNextIfNeeded()
    }

    /// Shows the next popup in the queue if nothing is currently showing.
    private func showNextIfNeeded() {
        guard currentPopup == nil, let next = popupQueue.first else { return }
        popupQueue.removeFirst()
        currentPopup = next
        showPopupPanel(for: next)
    }

    /// Shows the popup panel for a request.
    private func showPopupPanel(for request: ExtensionPopupRequest) {
        // Close any existing panel
        popupPanel?.close()

        // Create new panel
        let panel = ExtensionPopupPanel(request: request) { [weak self] in
            self?.closeCurrentPopup()
        }
        popupPanel = panel

        // Position near the top-right of the key window (where toolbar buttons usually are)
        if let keyWindow = NSApp.keyWindow {
            let windowFrame = keyWindow.frame
            let panelSize = panel.frame.size
            let x = windowFrame.maxX - panelSize.width - 20
            let y = windowFrame.maxY - panelSize.height - 60 // Below toolbar area
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
    }

    /// Called when the popup is closed.
    func closeCurrentPopup() {
        guard currentPopup != nil else { return }
        // Don't call close() here - this is called from the panel's willClose delegate
        // which means the panel is already closing
        popupPanel = nil
        currentPopup?.continuation.resume()
        currentPopup = nil
        showNextIfNeeded()
    }

    /// Called when the popup fails.
    func failCurrentPopup(error: any Error) {
        popupPanel?.close()
        popupPanel = nil
        currentPopup?.continuation.resume(throwing: error)
        currentPopup = nil
        showNextIfNeeded()
    }
}

// MARK: - Extension Popup Panel

/// A floating panel for displaying extension popups.
private class ExtensionPopupPanel: NSPanel, NSWindowDelegate {
    private let onClose: () -> Void
    private var isClosing = false

    init(request: ExtensionPopupRequest, onClose: @escaping () -> Void) {
        self.onClose = onClose

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false,
        )

        delegate = self
        title = request.extensionName
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        // Set minimum size
        minSize = NSSize(width: 300, height: 200)

        // Create the content view with the popup's web view
        let hostingView = NSHostingView(rootView: ExtensionPopupPanelContent(
            request: request,
            onClose: { [weak self] in self?.performClose(nil) },
        ))
        contentView = hostingView
    }

    func windowWillClose(_: Notification) {
        guard !isClosing else { return }
        isClosing = true
        onClose()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }
}

/// SwiftUI content for the popup panel.
private struct ExtensionPopupPanelContent: View {
    let request: ExtensionPopupRequest
    let onClose: () -> Void

    var body: some View {
        ExtensionPopupWebViewRepresentable(
            webView: request.popupWebView,
            onSizeChange: { _ in },
        )
        .frame(minWidth: 300, minHeight: 200)
    }
}

// MARK: - WebView Representable

private struct ExtensionPopupWebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    let onSizeChange: (CGSize) -> Void

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSizeChange: onSizeChange)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onSizeChange: (CGSize) -> Void

        init(onSizeChange: @escaping (CGSize) -> Void) {
            self.onSizeChange = onSizeChange
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // Try to get the content size after load
            webView.evaluateJavaScript("JSON.stringify({width: document.body.scrollWidth, height: document.body.scrollHeight})") { [weak self] result, _ in
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let size = try? JSONDecoder().decode(SizeData.self, from: data) else {
                    return
                }

                MainActor.assumeIsolated {
                    self?.onSizeChange(CGSize(width: CGFloat(size.width), height: CGFloat(size.height)))
                }
            }
        }

        private struct SizeData: Decodable {
            let width: Int
            let height: Int
        }
    }
}
