import Foundation
import Observation

/// Speed presets for agent visual feedback animations.
enum FeedbackSpeed: Sendable {
    /// Fast animations for experienced users (0.15s).
    case fast
    /// Natural, human-like pacing (0.35s). Default.
    case natural
    /// Slow animations for learning/demonstration (0.7s).
    case slow

    /// Base animation duration in seconds.
    var duration: Double {
        switch self {
        case .fast: 0.15
        case .natural: 0.35
        case .slow: 0.7
        }
    }

    /// Spring response parameter scaled to speed.
    var springResponse: Double {
        switch self {
        case .fast: 0.2
        case .natural: 0.35
        case .slow: 0.6
        }
    }

    /// Spring damping fraction.
    var dampingFraction: Double {
        0.7
    }
}

/// Style for element highlights.
enum HighlightStyle: Sendable, Equatable {
    /// Standard border highlight with subtle fill.
    case standard
    /// Pulsing highlight indicating imminent action.
    case aboutToAct
    /// Reading indicator — vertical scanning line.
    case reading
}

/// A single step in a feedback action sequence.
enum FeedbackStep: Sendable {
    /// Move cursor to a point within the given container bounds.
    case moveTo(CGPoint)
    /// Highlight an element rect with a given style.
    case highlight(CGRect, HighlightStyle)
    /// Highlight multiple element rects.
    case highlightMultiple([CGRect])
    /// Pause for a duration in seconds.
    case pause(Double)
    /// Perform a click animation at the current cursor position.
    case click
    /// Clear all highlights.
    case clearHighlights
}

/// State of the agent cursor.
enum AgentCursorState: Sendable, Equatable {
    case idle
    case hovering
    case clicking
    case reading
    case thinking
}

/// A single element highlight with an identifier for tracking.
struct ElementHighlightInfo: Identifiable, Equatable, Sendable {
    let id: UUID
    let rect: CGRect
    let style: HighlightStyle
    /// Normalized opacity for fade animations (0...1).
    var opacity: Double

    init(rect: CGRect, style: HighlightStyle, opacity: Double = 1.0) {
        self.id = UUID()
        self.rect = rect
        self.style = style
        self.opacity = opacity
    }
}

/// Coordinates all visual feedback for agent activity.
///
/// Manages cursor position, element highlights, and action sequences.
/// Views read published state to render overlays. Animated state uses
/// non-observed backing to avoid the `withAnimation` trap described in CLAUDE.md.
///
/// ## Usage
///
/// ```swift
/// @Environment(VisualFeedbackManager.self) var feedback
///
/// // Move cursor
/// feedback.moveCursor(to: CGPoint(x: 200, y: 300), in: webViewBounds)
///
/// // Run a sequence
/// feedback.performAction(sequence: [
///     .moveTo(CGPoint(x: 100, y: 200)),
///     .highlight(elementRect, .aboutToAct),
///     .pause(0.5),
///     .click,
///     .clearHighlights,
/// ])
/// ```
@Observable
@MainActor
final class VisualFeedbackManager {
    // MARK: - Observable State

    /// Whether the visual feedback system is active (cursor visible, etc.).
    private(set) var isActive: Bool = false

    /// Current cursor state for rendering.
    private(set) var cursorState: AgentCursorState = .idle

    /// Target cursor position in overlay coordinate space.
    /// Views should animate to this position using explicit `.animation()` modifiers.
    private(set) var cursorPosition: CGPoint = .zero

    /// Active element highlights.
    private(set) var highlights: [ElementHighlightInfo] = []

    /// Animation speed preset.
    var speed: FeedbackSpeed = .natural

    // MARK: - Non-Observable State

    /// Current action sequence task, cancellable for interruption.
    @ObservationIgnored
    private var sequenceTask: Task<Void, Never>?

    /// Whether an action sequence is currently running.
    @ObservationIgnored
    private(set) var isRunningSequence: Bool = false

    // MARK: - Cursor Control

    /// Shows the cursor and activates the visual feedback overlay.
    func activate() {
        isActive = true
    }

    /// Hides the cursor and deactivates all visual feedback.
    func deactivate() {
        cancel()
        isActive = false
        cursorState = .idle
        highlights.removeAll()
    }

    /// Moves the cursor to a position within the given container bounds.
    ///
    /// The position is clamped to the container. The view layer applies
    /// spring animation via explicit `.animation()` modifier — no `withAnimation` here.
    ///
    /// - Parameters:
    ///   - point: Target position in web content coordinate space.
    ///   - containerBounds: Bounds of the overlay container for clamping.
    func moveCursor(to point: CGPoint, in containerBounds: CGRect) {
        let clamped = CGPoint(
            x: min(max(point.x, containerBounds.minX), containerBounds.maxX),
            y: min(max(point.y, containerBounds.minY), containerBounds.maxY),
        )
        cursorPosition = clamped
        if cursorState == .idle {
            cursorState = .hovering
        }
    }

    /// Sets the cursor state directly.
    func setCursorState(_ state: AgentCursorState) {
        cursorState = state
    }

    // MARK: - Highlight Control

    /// Highlights a single element rect with a given style.
    ///
    /// - Parameters:
    ///   - rect: Element bounding rect in overlay coordinate space.
    ///   - style: Visual style for the highlight.
    func highlightElement(rect: CGRect, style: HighlightStyle = .standard) {
        let info = ElementHighlightInfo(rect: rect, style: style)
        highlights.append(info)
    }

    /// Highlights multiple elements simultaneously.
    ///
    /// - Parameter rects: Element bounding rects in overlay coordinate space.
    func highlightElements(rects: [CGRect]) {
        let infos = rects.map { ElementHighlightInfo(rect: $0, style: .standard) }
        highlights.append(contentsOf: infos)
    }

    /// Removes all active highlights.
    func clearHighlights() {
        highlights.removeAll()
    }

    // MARK: - Action Sequences

    /// Performs a sequenced action (move, highlight, pause, click).
    ///
    /// Cancels any currently running sequence. Each step executes in order
    /// with appropriate delays based on the current speed setting.
    ///
    /// - Parameter sequence: Ordered list of feedback steps.
    func performAction(sequence: [FeedbackStep]) {
        // Cancel any existing sequence
        sequenceTask?.cancel()

        isRunningSequence = true

        sequenceTask = Task { [weak self] in
            guard let self else { return }

            for step in sequence {
                guard !Task.isCancelled else { break }

                switch step {
                case let .moveTo(point):
                    cursorPosition = point
                    cursorState = .hovering
                    try? await Task.sleep(for: .milliseconds(Int(speed.duration * 1_000)))

                case let .highlight(rect, style):
                    highlightElement(rect: rect, style: style)
                    try? await Task.sleep(for: .milliseconds(Int(speed.duration * 500)))

                case let .highlightMultiple(rects):
                    highlightElements(rects: rects)
                    try? await Task.sleep(for: .milliseconds(Int(speed.duration * 500)))

                case let .pause(duration):
                    try? await Task.sleep(for: .milliseconds(Int(duration * 1_000)))

                case .click:
                    cursorState = .clicking
                    // Brief click animation duration
                    try? await Task.sleep(for: .milliseconds(200))
                    cursorState = .hovering

                case .clearHighlights:
                    clearHighlights()
                }
            }

            if !Task.isCancelled {
                isRunningSequence = false
            }
        }
    }

    /// Cancels any currently running action sequence.
    func cancel() {
        sequenceTask?.cancel()
        sequenceTask = nil
        isRunningSequence = false
    }
}
