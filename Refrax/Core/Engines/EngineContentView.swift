import AppKit
import SwiftUI

/// Displays a plug-in engine session's content view.
///
/// The session owns its view; this host only re-parents it, so the page's
/// rendering state survives SwiftUI rebuilding the surrounding hierarchy.
struct EngineContentView: NSViewRepresentable {
    let session: any EnginePageSession

    func makeNSView(context _: Context) -> EngineHostView {
        let host = EngineHostView()
        host.attach(session.contentView)
        return host
    }

    func updateNSView(_ host: EngineHostView, context _: Context) {
        host.attach(session.contentView)
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
