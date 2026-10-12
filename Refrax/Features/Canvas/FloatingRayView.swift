import SwiftUI

/// A glowing ray from the control that displaced a page to the page's new place in
/// the floating layer: it draws along its length, bends once as it enters the tab's
/// glass, lands as a bright spot that pulses once, and fades. With Reduce Motion the
/// spot alone marks the place.
struct FloatingRayView: View {
    let path: FloatingRayPath
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var spotScale: CGFloat = 1
    @State private var spotOpacity: Double = 0

    private enum Layout {
        static let glowWidth: CGFloat = 10
        static let glowBlur: CGFloat = 8
        static let coreWidth: CGFloat = 2
        static let spotRadius: CGFloat = 5
        static let spotGlowRadius: CGFloat = 11
        static let pulseScale: CGFloat = 1.7
        static let travel: Duration = .milliseconds(500)
        static let hold: Duration = .milliseconds(300)
        static let fade: Duration = .milliseconds(300)
        static let highlight: Duration = .milliseconds(600)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !reduceMotion {
                ray
            }
            spot
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await play() }
    }

    private var ray: some View {
        ZStack {
            RayShape(path: path)
                .trim(from: 0, to: progress)
                .stroke(Color.appAccentColor.opacity(0.75), style: StrokeStyle(lineWidth: Layout.glowWidth, lineCap: .round, lineJoin: .round))
                .blur(radius: Layout.glowBlur)
            RayShape(path: path)
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: Layout.coreWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private var spot: some View {
        ZStack {
            Circle()
                .fill(Color.appAccentColor.opacity(0.8))
                .frame(width: Layout.spotGlowRadius * 2, height: Layout.spotGlowRadius * 2)
                .blur(radius: Layout.glowBlur)
            Circle()
                .fill(.white)
                .frame(width: Layout.spotRadius * 2, height: Layout.spotRadius * 2)
        }
        .scaleEffect(spotScale)
        .opacity(spotOpacity)
        .position(path.end)
    }

    private func play() async {
        if reduceMotion {
            spotOpacity = 1
            try? await Task.sleep(for: Layout.highlight)
        } else {
            withAnimation(.easeOut(duration: Self.seconds(Layout.travel))) { progress = 1 }
            try? await Task.sleep(for: Layout.travel)
            guard !Task.isCancelled else { return }
            spotOpacity = 1
            withAnimation(.easeOut(duration: Self.seconds(Layout.hold) / 2)) { spotScale = Layout.pulseScale }
            try? await Task.sleep(for: Layout.hold / 2)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: Self.seconds(Layout.hold) / 2)) { spotScale = 1 }
            try? await Task.sleep(for: Layout.hold / 2)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: Self.seconds(Layout.fade))) { opacity = 0 }
            try? await Task.sleep(for: Layout.fade)
        }
        guard !Task.isCancelled else { return }
        onFinish()
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

/// The ray's two runs as one open path.
private nonisolated struct RayShape: Shape {
    let path: FloatingRayPath

    func path(in _: CGRect) -> Path {
        var shape = Path()
        shape.move(to: path.start)
        shape.addLine(to: path.bend)
        shape.addLine(to: path.end)
        return shape
    }
}
