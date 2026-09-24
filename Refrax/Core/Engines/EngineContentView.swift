import AppKit
import SwiftUI

/// Displays an engine page's view.
///
/// The page owns its view; this host only re-parents it, so the page's
/// rendering state survives SwiftUI rebuilding the surrounding hierarchy.
struct EngineContentView: NSViewRepresentable {
    let page: any EnginePage

    func makeNSView(context _: Context) -> EngineHostView {
        let host = EngineHostView()
        host.attach(page.view)
        return host
    }

    func updateNSView(_ host: EngineHostView, context _: Context) {
        host.attach(page.view)
    }

    static func dismantleNSView(_ host: EngineHostView, coordinator _: ()) {
        host.detach()
    }
}

/// A container that keeps a single engine view filling its bounds.
final class EngineHostView: NSView {
    private weak var hostedView: NSView?

    override var isFlipped: Bool {
        true
    }

    func attach(_ view: NSView) {
        guard hostedView !== view || view.superview !== self else { return }
        detach()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        hostedView = view
    }

    func detach() {
        guard let hostedView, hostedView.superview === self else { return }
        hostedView.removeFromSuperview()
        self.hostedView = nil
    }
}
