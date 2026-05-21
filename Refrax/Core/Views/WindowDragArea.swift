import SwiftUI

/// A SwiftUI view that enables window dragging from its area.
///
/// Wraps content in an NSView that responds to mouse drags by moving the window.
/// Used for custom title bar areas where the standard window drag behavior
/// should be enabled.
///
/// ## Usage
///
/// ```swift
/// WindowDragArea {
///     Text("Drag me to move window")
///         .frame(height: 44)
/// }
/// ```
struct WindowDragArea<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context _: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context _: Context) {
        if let hostingView = nsView.subviews.first as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

/// NSView subclass that enables window dragging from its area.
final class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
