import SwiftUI

/// Plays a set of ``LightPath`` values through one journey: the beams travel from their
/// start to their end with an ease-out, hold while the tip spot pulses once, then fade.
/// Under Reduce Motion the whole path shows at once, holds, and fades.
///
/// `onFinish` is called once, on the main actor, when the fade ends.
struct LightTravel: View {
    /// How long each phase of the journey lasts.
    nonisolated struct Timing: Equatable, Sendable {
        var travel: Duration = .milliseconds(500)
        var hold: Duration = .milliseconds(300)
        var fade: Duration = .milliseconds(300)
        /// How long the full path holds under Reduce Motion before it fades.
        var reducedMotionHold: Duration = .milliseconds(600)
        /// Peak scale of the tip spot's pulse during the hold.
        var pulseScale: CGFloat = 1.7

        static let `default` = Timing()

        /// The journey's length from first light to the end of the fade.
        func total(reduceMotion: Bool) -> TimeInterval {
            if reduceMotion {
                return Self.seconds(reducedMotionHold) + Self.seconds(fade)
            }
            return Self.seconds(travel) + Self.seconds(hold) + Self.seconds(fade)
        }

        /// The state of the beams `elapsed` seconds into the journey.
        func frame(at elapsed: TimeInterval, reduceMotion: Bool) -> Frame {
            let fadeSeconds = Self.seconds(fade)
            let holdSeconds = reduceMotion ? Self.seconds(reducedMotionHold) : Self.seconds(hold)
            let travelSeconds = reduceMotion ? 0 : Self.seconds(travel)
            let time = max(elapsed, 0)

            if time < travelSeconds {
                return Frame(progress: Self.easeOut(time / travelSeconds), intensity: 1, spotScale: 1, isFinished: false)
            }
            let held = time - travelSeconds
            if held < holdSeconds {
                let pulse = reduceMotion ? 0 : sin(.pi * held / holdSeconds)
                return Frame(progress: 1, intensity: 1, spotScale: 1 + (pulseScale - 1) * pulse, isFinished: false)
            }
            let faded = held - holdSeconds
            guard faded < fadeSeconds else {
                return Frame(progress: 1, intensity: 0, spotScale: 1, isFinished: true)
            }
            return Frame(progress: 1, intensity: 1 - Self.easeIn(faded / fadeSeconds), spotScale: 1, isFinished: false)
        }

        private static func easeOut(_ t: Double) -> Double {
            1 - pow(1 - t, 3)
        }

        private static func easeIn(_ t: Double) -> Double {
            t * t
        }

        private static func seconds(_ duration: Duration) -> TimeInterval {
            let (seconds, attoseconds) = duration.components
            return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
        }
    }

    /// The beams' state at one moment of the journey.
    nonisolated struct Frame: Equatable, Sendable {
        var progress: Double
        var intensity: Double
        var spotScale: CGFloat
        var isFinished: Bool
    }

    let paths: [LightPath]
    var timing: Timing = .default
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(paused: finished)) { context in
            let frame = timing.frame(at: elapsed(at: context.date), reduceMotion: reduceMotion)
            LightLayer(paths: paths.map { $0.applying(frame) })
                .onChange(of: frame.isFinished) { _, isFinished in
                    guard isFinished, !finished else { return }
                    finished = true
                    onFinish()
                }
        }
        .onAppear { start = .now }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        guard let start else { return 0 }
        return date.timeIntervalSince(start)
    }
}
