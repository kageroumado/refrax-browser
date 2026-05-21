import AppKit
import SwiftUI

/// Observable handler for two-finger horizontal swipe gestures to navigate between spaces.
///
/// Implements a state machine with four states:
/// - `.idle`: No gesture active
/// - `.dragging`: User is actively dragging
/// - `.switching`: Animating transition to next/previous space
/// - `.bouncing`: Rubber-band bounce at first/last space
///
/// The handler provides a `translationOffset` for animating the sidebar content
/// during the gesture, and triggers space switches via `SpaceManager`.
///
/// ## Gesture Recognition
///
/// Uses `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)` to intercept
/// trackpad two-finger horizontal swipes. The sidebar's `ScrollView` is vertical-only,
/// so horizontal scroll deltas pass through unused. This approach avoids conflicts
/// with the scroll view's own gesture handling.
@Observable
final class SpaceSwipeGestureHandler {
    // MARK: - State

    enum GestureState: Equatable {
        case idle
        case dragging(translation: CGFloat)
        case switching(direction: Direction)
        case bouncing(direction: Direction)
    }

    enum Direction {
        case left // Swipe left → next space (index increases)
        case right // Swipe right → previous space (index decreases)
    }

    private(set) var state: GestureState = .idle

    // MARK: - Adjacent Space Data

    /// The ID of the space being previewed during a swipe gesture.
    private(set) var adjacentSpaceID: UUID?

    /// Cached pinned items for the adjacent space preview.
    private(set) var adjacentPinnedItems: [TabListItem] = []

    /// Cached normal items for the adjacent space preview.
    private(set) var adjacentNormalItems: [TabListItem] = []

    // MARK: - Dependencies

    private weak var windowState: WindowState?
    private weak var spaceManager: SpaceManager?
    private weak var settings: BrowserSettings?
    private weak var transitionCoordinator: Sidebar.TransitionCoordinator?
    weak var layoutManager: Sidebar.LayoutManager?

    // MARK: - Thresholds

    private let switchThreshold: CGFloat = 100 // Distance to trigger switch
    private let velocityThreshold: CGFloat = 500 // Velocity to trigger switch
    private let bounceDistance: CGFloat = 30 // Max rubber-band distance

    // MARK: - Computed Properties

    /// The horizontal offset to apply to sidebar content during the gesture.
    var translationOffset: CGFloat {
        switch state {
        case .idle:
            0
        case let .dragging(translation):
            clampedTranslation(translation)
        case let .switching(direction):
            direction == .left ? -switchThreshold : switchThreshold
        case let .bouncing(direction):
            direction == .left ? -bounceDistance : bounceDistance
        }
    }

    /// Whether the handler is currently animating (switching or bouncing).
    var isAnimating: Bool {
        switch state {
        case .switching, .bouncing: true
        default: false
        }
    }

    /// Whether space swipe gesture is enabled.
    /// Returns false if disabled in settings or if there's only one space.
    var isEnabled: Bool {
        guard settings?.spaceSwipeGestureEnabled ?? true else { return false }
        guard let spaceManager else { return false }
        return spaceManager.spaces.count > 1
    }

    // MARK: - Initialization

    func configure(
        windowState: WindowState,
        spaceManager: SpaceManager,
        settings: BrowserSettings,
        transitionCoordinator: Sidebar.TransitionCoordinator,
        layoutManager: Sidebar.LayoutManager,
    ) {
        self.windowState = windowState
        self.spaceManager = spaceManager
        self.settings = settings
        self.transitionCoordinator = transitionCoordinator
        self.layoutManager = layoutManager
    }

    // MARK: - Gesture Handling

    /// Handle drag gesture change.
    ///
    /// Called continuously as the user drags. Only processes horizontal drags
    /// when the gesture is enabled and not already animating.
    func handleDragChange(_ translation: CGFloat) {
        guard isEnabled else { return }
        guard !isAnimating else { return }

        // Populate adjacent space data when direction changes or first established
        let direction: Direction = translation > 0 ? .right : .left
        let targetSpace = adjacentSpace(direction: direction)

        if targetSpace?.id != adjacentSpaceID {
            if let targetSpace {
                adjacentSpaceID = targetSpace.id
                if let cached = layoutManager?.cachedItemsForSpace(targetSpace.id) {
                    adjacentPinnedItems = cached.pinned
                    adjacentNormalItems = cached.normal
                } else {
                    // Build and cache on demand
                    layoutManager?.buildLayoutForSpace(targetSpace)
                    if let cached = layoutManager?.cachedItemsForSpace(targetSpace.id) {
                        adjacentPinnedItems = cached.pinned
                        adjacentNormalItems = cached.normal
                    }
                }
            } else {
                clearAdjacentSpaceData()
            }
        }

        state = .dragging(translation: translation)
    }

    /// Handle drag gesture end.
    ///
    /// Determines whether to switch spaces, bounce, or return to idle
    /// based on the final translation and velocity.
    func handleDragEnd(_ translation: CGFloat, velocity: CGFloat) {
        guard isEnabled else {
            state = .idle
            clearAdjacentSpaceData()
            return
        }

        // If we're not in dragging state, ignore
        guard case .dragging = state else {
            state = .idle
            clearAdjacentSpaceData()
            return
        }

        // Determine if gesture should trigger switch
        let shouldSwitch = abs(translation) > switchThreshold || abs(velocity) > velocityThreshold
        let direction: Direction = translation > 0 ? .right : .left

        if shouldSwitch {
            if let nextSpace = adjacentSpace(direction: direction) {
                // Switch to adjacent space — performSwitch resets gesture state
                // and delegates animation to the transition coordinator
                performSwitch(to: nextSpace, direction: direction)
            } else {
                // At edge - bounce
                state = .bouncing(direction: direction)
                performBounce()
            }
        } else {
            // Not enough distance - spring back to idle
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state = .idle
            }
            clearAdjacentSpaceData()
        }
    }

    /// Cancel any in-progress gesture.
    func cancelGesture() {
        guard case .dragging = state else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            state = .idle
        }
        clearAdjacentSpaceData()
    }

    // MARK: - Private Methods

    private func clearAdjacentSpaceData() {
        adjacentSpaceID = nil
        adjacentPinnedItems = []
        adjacentNormalItems = []
    }

    private func adjacentSpace(direction: Direction) -> Space? {
        guard let windowState,
              let spaceManager,
              let currentSpaceID = windowState.activeSpaceID
        else { return nil }

        let spaces = spaceManager.spaces
        guard let currentIndex = spaces.firstIndex(where: { $0.id == currentSpaceID })
        else { return nil }

        switch direction {
        case .left: // Next space
            let nextIndex = currentIndex + 1
            return nextIndex < spaces.count ? spaces[nextIndex] : nil
        case .right: // Previous space
            let prevIndex = currentIndex - 1
            return prevIndex >= 0 ? spaces[prevIndex] : nil
        }
    }

    private func performSwitch(to space: Space, direction _: Direction) {
        guard let windowState, let spaceManager else {
            state = .idle
            clearAdjacentSpaceData()
            return
        }

        // Reset gesture offset immediately — the transition coordinator
        // takes over animation from here with its own out/in sequencing
        state = .idle
        clearAdjacentSpaceData()

        let spaces = spaceManager.spaces
        let oldIndex = spaces.firstIndex(where: { $0.id == windowState.activeSpaceID }) ?? 0
        let newIndex = spaces.firstIndex(where: { $0.id == space.id }) ?? 0

        // Use the coordinator's proper out/in animation sequence
        transitionCoordinator?.animateSpaceChange(from: oldIndex, to: newIndex) {
            Task {
                await spaceManager.switchToSpace(space, for: windowState)
            }
        }
    }

    private func performBounce() {
        clearAdjacentSpaceData()
        // Rubber-band return animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            state = .idle
        }
    }

    private func clampedTranslation(_ translation: CGFloat) -> CGFloat {
        let direction: Direction = translation > 0 ? .right : .left
        let hasAdjacentSpace = adjacentSpace(direction: direction) != nil

        if hasAdjacentSpace {
            // Allow full translation up to a reasonable limit
            return translation.clamped(to: -200 ... 200)
        } else {
            // Rubber-band effect at edge - apply resistance
            let resistance: CGFloat = 0.3
            let resistedTranslation = translation * resistance
            return resistedTranslation.clamped(to: -bounceDistance ... bounceDistance)
        }
    }
}

// MARK: - Scroll Wheel Event Monitor

/// NSView that installs a local scroll wheel event monitor for space swipe detection.
///
/// Trackpad two-finger swipes generate `scrollWheel` events with `hasPreciseScrollingDeltas`.
/// The sidebar's ScrollView is vertical-only, so horizontal scroll delta passes through
/// unused. We intercept these horizontal deltas for space switching.
///
/// This approach replaces the previous `NSPanGestureRecognizer` which failed because:
/// (a) the gesture view had zero size in `.background`
/// (b) `hitTest` returned nil
/// (c) it conflicted with ScrollView's own two-finger scroll handling
private final class SpaceSwipeScrollMonitorView: NSView {
    var handler: SpaceSwipeGestureHandler?
    private var eventMonitor: Any?

    // Scroll wheel tracking state
    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private var isTracking = false
    private var directionDecided = false
    private var isHorizontalGesture = false
    private var lastEventTimestamp: TimeInterval = 0

    /// Minimum total delta to accumulate before deciding gesture direction.
    private let directionDecisionThreshold: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event) ?? event
        }
    }

    func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        // Only handle trackpad events (precise scrolling deltas)
        guard event.hasPreciseScrollingDeltas else { return event }

        // Check if the event is within the sidebar's scroll view bounds
        guard let scrollView = enclosingScrollView ?? findEnclosingScrollView(),
              scrollView.window != nil
        else { return event }

        let locationInWindow = event.locationInWindow
        let locationInScrollView = scrollView.convert(locationInWindow, from: nil)
        guard scrollView.bounds.contains(locationInScrollView) else {
            // Event outside sidebar - reset if we were tracking
            if isTracking {
                resetTrackingState()
            }
            return event
        }

        // Check if gesture is enabled
        guard let handler, handler.isEnabled else { return event }

        switch event.phase {
        case .began:
            accumulatedDeltaX = event.scrollingDeltaX
            accumulatedDeltaY = event.scrollingDeltaY
            isTracking = true
            directionDecided = false
            isHorizontalGesture = false
            lastEventTimestamp = event.timestamp

        case .changed where isTracking:
            accumulatedDeltaX += event.scrollingDeltaX
            accumulatedDeltaY += event.scrollingDeltaY
            lastEventTimestamp = event.timestamp

            if !directionDecided {
                let totalDelta = abs(accumulatedDeltaX) + abs(accumulatedDeltaY)
                if totalDelta > directionDecisionThreshold {
                    directionDecided = true
                    isHorizontalGesture = abs(accumulatedDeltaX) > abs(accumulatedDeltaY)

                    if isHorizontalGesture {
                        // Start tracking — feed accumulated delta
                        MainActor.assumeIsolated {
                            handler.handleDragChange(accumulatedDeltaX)
                        }
                    }
                }
            } else if isHorizontalGesture {
                MainActor.assumeIsolated {
                    handler.handleDragChange(accumulatedDeltaX)
                }
            }

        case .ended where isTracking:
            if isHorizontalGesture {
                // Estimate velocity from recent delta and time
                let velocity = estimateVelocity(event)
                MainActor.assumeIsolated {
                    handler.handleDragEnd(accumulatedDeltaX, velocity: velocity)
                }
            }
            resetTrackingState()

        case .cancelled where isTracking:
            if isHorizontalGesture {
                MainActor.assumeIsolated {
                    handler.cancelGesture()
                }
            }
            resetTrackingState()

        default:
            break
        }

        // Don't consume the event — let ScrollView get it too.
        // ScrollView ignores horizontal delta for vertical-only scrolling.
        return event
    }

    private func resetTrackingState() {
        accumulatedDeltaX = 0
        accumulatedDeltaY = 0
        isTracking = false
        directionDecided = false
        isHorizontalGesture = false
    }

    private func estimateVelocity(_ event: NSEvent) -> CGFloat {
        // Use the final event's delta as a proxy for velocity
        // Scale up since scroll deltas are typically small per-event
        event.scrollingDeltaX * 10
    }

    /// Walk the view hierarchy to find the enclosing scroll view.
    private func findEnclosingScrollView() -> NSScrollView? {
        var view: NSView? = superview
        while let current = view {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
        // Fully transparent to hit testing
        nil
    }
}

// MARK: - NSViewRepresentable

/// NSViewRepresentable wrapper that manages the scroll wheel event monitor lifecycle.
private struct SpaceSwipeScrollMonitorRepresentable: NSViewRepresentable {
    let handler: SpaceSwipeGestureHandler

    func makeNSView(context _: Context) -> SpaceSwipeScrollMonitorView {
        let view = SpaceSwipeScrollMonitorView()
        view.handler = handler
        view.installMonitor()
        return view
    }

    func updateNSView(_ nsView: SpaceSwipeScrollMonitorView, context _: Context) {
        nsView.handler = handler
    }

    static func dismantleNSView(_ nsView: SpaceSwipeScrollMonitorView, coordinator _: ()) {
        nsView.removeMonitor()
    }
}

// MARK: - View Modifier

/// A SwiftUI view modifier that enables two-finger swipe navigation between spaces.
///
/// Apply this to the sidebar scroll view. Swipe left to go to the next space,
/// swipe right to go to the previous space.
///
/// Uses a local scroll wheel event monitor to intercept trackpad two-finger
/// horizontal swipes without conflicting with the scroll view's vertical scrolling.
///
/// ## Usage
///
/// ```swift
/// SidebarContent()
///     .sidebarSpaceSwipeGesture()
/// ```
struct SidebarSpaceSwipeGestureModifier: ViewModifier {
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(WindowState.self) private var windowState
    @Environment(BrowserSettings.self) private var settings
    @Environment(Sidebar.TransitionCoordinator.self) private var transitionCoordinator
    @Environment(Sidebar.LayoutManager.self) private var layoutManager

    /// External handler, shared with the parent Sidebar for adjacent space preview.
    let handler: SpaceSwipeGestureHandler

    func body(content: Content) -> some View {
        content
            .offset(x: handler.translationOffset)
            .animation(handler.isAnimating ? .interactiveSpring : nil, value: handler.translationOffset)
            .background {
                SpaceSwipeScrollMonitorRepresentable(handler: handler)
            }
            .onAppear {
                handler.configure(
                    windowState: windowState,
                    spaceManager: spaceManager,
                    settings: settings,
                    transitionCoordinator: transitionCoordinator,
                    layoutManager: layoutManager,
                )
            }
            .onChange(of: windowState.activeSpaceID) { _, _ in
                // Reset gesture state when space changes externally
                handler.cancelGesture()
            }
            .accessibilityAction(.escape) {
                handler.cancelGesture()
            }
    }
}

// MARK: - View Extension

extension View {
    /// Adds two-finger swipe gesture for navigating between spaces.
    ///
    /// Apply to sidebar content only. Swipe left to go to the next space,
    /// swipe right to go to the previous space.
    ///
    /// - Parameter handler: Shared handler instance for reading gesture state
    ///   from the parent view (e.g., to render adjacent space preview).
    ///
    /// Features:
    /// - Two-finger horizontal drag gesture via scroll wheel event monitor
    /// - Rubber-band bounce effect at first/last space
    /// - Adjacent space tab preview during swipe
    /// - Respects `BrowserSettings.spaceSwipeGestureEnabled`
    func sidebarSpaceSwipeGesture(handler: SpaceSwipeGestureHandler) -> some View {
        modifier(SidebarSpaceSwipeGestureModifier(handler: handler))
    }
}

// MARK: - Helper Extensions

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
