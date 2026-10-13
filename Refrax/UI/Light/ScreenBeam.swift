import AppKit
import SwiftUI

/// A borderless, transparent panel above the browser's windows that takes no clicks and
/// never becomes key: the surface for things that travel between windows.
final class PassThroughPanel: NSPanel {
    init(frame: CGRect, hasShadow: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        self.hasShadow = hasShadow
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// A beam between two places on screen, such as a card and the window it just became. It is
/// drawn by the light engine in a panel spanning both, and the panel closes when the beam
/// has faded.
@MainActor
enum ScreenBeam {
    /// The panel's rectangle for a beam between `source` and `destination`, in screen
    /// coordinates, with room for the halo on every side.
    nonisolated static func panelFrame(from source: CGRect, to destination: CGRect) -> CGRect {
        let margin = LightPath.Layout.glowWidth
        return source.union(destination).insetBy(dx: -margin, dy: -margin)
    }

    /// `rect`, in screen coordinates, measured from the top-left corner of `panel`.
    nonisolated static func local(_ rect: CGRect, in panel: CGRect) -> CGRect {
        CGRect(x: rect.minX - panel.minX, y: panel.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private static var panels: [ObjectIdentifier: PassThroughPanel] = [:]

    /// Plays a beam from `source` to `destination`, both in screen coordinates.
    static func play(from source: CGRect, to destination: CGRect, style: LightStyle = .displaced) {
        let frame = panelFrame(from: source, to: destination)
        let bounds = CGRect(origin: .zero, size: frame.size)
        let ray = FloatingRayPath(from: local(source, in: frame), to: local(destination, in: frame), in: bounds)
        let panel = PassThroughPanel(frame: frame, hasShadow: false)
        let id = ObjectIdentifier(panel)
        let beam = LightTravel(paths: [style.path(ray: ray, color: style.color(space: nil))], timing: style.timing) {
            panels.removeValue(forKey: id)?.close()
        }
        panel.contentView = NSHostingView(rootView: beam.frame(width: frame.width, height: frame.height).accessibilityHidden(true))
        panels[id] = panel
        panel.orderFrontRegardless()
    }
}
