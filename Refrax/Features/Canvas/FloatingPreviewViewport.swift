import AppKit
import SwiftUI

/// Keeps desktop layout and AppKit event coordinates aligned at every preview scale.
struct FloatingPreviewViewport<Content: View>: NSViewRepresentable {
    let viewportSize: CGSize
    var region: FloatingPageRegion? = nil
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> FloatingPreviewScaleView {
        let host = NSHostingView(rootView: HostedContent(content: content(), environment: context.environment))
        host.sizingOptions = []
        return FloatingPreviewScaleView(content: host, viewportSize: viewportSize)
    }

    func updateNSView(_ view: FloatingPreviewScaleView, context: Context) {
        if let host = view.content as? NSHostingView<HostedContent> {
            host.rootView = HostedContent(content: content(), environment: context.environment)
        }
        view.viewportSize = viewportSize
        view.region = region
    }

    private struct HostedContent: View {
        let content: Content
        let environment: EnvironmentValues

        var body: some View {
            content.environment(\.self, environment)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: FloatingPreviewScaleView, context _: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// The parent scales coordinates; its child always receives a full desktop-sized frame.
final class FloatingPreviewScaleView: NSView {
    let content: NSView
    private let surface = FlippedSurface()
    var viewportSize: CGSize {
        didSet { needsLayout = true }
    }

    var region: FloatingPageRegion? {
        didSet { needsLayout = true }
    }

    override var isFlipped: Bool {
        true
    }

    init(content: NSView, viewportSize: CGSize) {
        self.content = content
        self.viewportSize = viewportSize
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(surface)
        surface.addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard viewportSize.width > 0, viewportSize.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        if let region, region.isValid {
            surface.frame = region.surfaceFrame(in: bounds)
            surface.bounds = CGRect(origin: .zero, size: region.viewportSize)
            content.frame = surface.bounds
            return
        }
        let scale = min(bounds.width / viewportSize.width, bounds.height / viewportSize.height)
        let size = CGSize(width: viewportSize.width * scale, height: viewportSize.height * scale)
        surface.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height,
        )
        surface.bounds = CGRect(origin: .zero, size: viewportSize)
        content.frame = surface.bounds
    }

    private final class FlippedSurface: NSView {
        override var isFlipped: Bool {
            true
        }
    }
}
