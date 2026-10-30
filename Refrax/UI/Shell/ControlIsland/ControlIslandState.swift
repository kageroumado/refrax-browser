import Foundation
import Observation

/// Per-window disclosure, rest, and placement state for the browser controls.
@Observable
final class ControlIslandState {
    var placement: ControlIslandPlacement
    let configuration: ControlIslandConfiguration
    let tabInfo = ControlIslandTabInfoState()
    var showsCustomization = false
    var isHovered = false
    var hasKeyboardFocus = false
    var isPresenting = false
    var showsAddress = false
    var isDragging = false
    var isReorderingFavorites = false
    /// The space sheet or confirmation the island shows next: New Space, Edit, Delete, Clear.
    var spaceRequest: ControlIslandSpaceRequest?
    /// The pointer is far from the controls or has been still: the glass clears and the glyphs recede.
    private(set) var isQuiet = false
    var focusRequest = 0
    var dismissalRequest = 0
    var pageFocusRequest = 0
    /// The rail's frame in window content coordinates, for anything that points at it.
    var railFrame: CGRect = .zero
    /// The rail's frame where it rests, kept while it hides at the edge: a coupled File Island
    /// is placed under it.
    var railLayoutFrame: CGRect = .zero
    /// A File Island coupled under the rail, zero while there is none: the pointer near it is
    /// near the rail, the edge beside it brings the rail back, and the rail stays on screen while
    /// the island is in use, so the two hide and return together.
    var companionFrame: CGRect = .zero
    @ObservationIgnored var companionIsEngaged = false
    /// Each visible control's frame in window content coordinates.
    private(set) var itemFrames: [ControlIslandItem: CGRect] = [:]
    /// The page card's frame in window content coordinates while it is unfolded; zero while it is away.
    var pageCardFrame: CGRect = .zero
    @ObservationIgnored var hitRegions: [CGRect] = []
    @ObservationIgnored var pointerMoved: ((CGPoint) -> Void)?
    @ObservationIgnored var lastPointerMovement = Date.distantPast
    @ObservationIgnored private var hoverPath = ControlIslandHoverPath()
    @ObservationIgnored private var quietTask: Task<Void, Never>?
    /// The end of the latest ``holdAwake(for:now:)``.
    private var awakeUntil = Date.distantPast
    @ObservationIgnored private var awakeHoldTask: Task<Void, Never>?
    /// Away past the window edge the rail is snapped to; meaningful while ``hiddenEdge`` is set.
    private var isTuckedAway: Bool
    /// What brought a hidden rail back; Escape sends a rail the pointer brought back away again.
    private(set) var edgeReveal: EdgeReveal?
    /// The strip along the window edge that brings a hidden rail back, in window content coordinates.
    @ObservationIgnored var revealStrip: CGRect = .zero
    /// Something beyond the rail needs it on screen: the tour, the lens, or a drag toward it.
    @ObservationIgnored private(set) var isNeededOnScreen = false
    @ObservationIgnored private var lastNearPointer = Date()
    @ObservationIgnored private var pointerIsNear = false
    @ObservationIgnored private var edgeHideTask: Task<Void, Never>?
    /// The window's content, in its own coordinates, for the flap's reach.
    @ObservationIgnored var areaBounds: CGRect = .zero
    /// A pointer this close to the hidden rail's edge, at the flap's height, brings the rail back.
    static let flapReach: CGFloat = 120

    @ObservationIgnored private let defaults: UserDefaults?
    private static let placementKey = "controlIsland.placement"

    /// Pointer travel this close to the controls keeps them awake.
    static let nearDistance: CGFloat = 160
    /// A pointer resting past this distance after waking the controls lets them rest again.
    static let farDistance: CGFloat = 220
    static let stillDelay: TimeInterval = 2.5
    /// How long a Look keeps the rail awake, so the page card's return row is seen.
    static let visitHold: TimeInterval = 4

    init(defaults: UserDefaults? = .standard, configuration: ControlIslandConfiguration = .shared) {
        self.defaults = defaults
        self.configuration = configuration
        let placement = defaults?.data(forKey: Self.placementKey)
            .flatMap { try? JSONDecoder().decode(ControlIslandPlacement.self, from: $0) } ?? .init()
        self.placement = placement
        self.isTuckedAway = configuration.hidesAtEdge && placement.horizontalEdge != nil
    }

    /// The window edge the rail hides past: the side it is snapped to, while Hide at the Edge is on.
    var hiddenEdge: ControlIslandPlacement.Edge? {
        configuration.hidesAtEdge ? placement.horizontalEdge : nil
    }

    /// The rail is away past its window edge and takes no pointer.
    var isHiddenAtEdge: Bool {
        isTuckedAway && hiddenEdge != nil
    }

    /// Where light that comes from the rail starts, in window content coordinates: the rail
    /// itself, or, while it hides at the edge, the flap that marks it on that edge. Zero
    /// before the rail has been laid out.
    var lightSource: CGRect {
        guard isHiddenAtEdge, let edge = hiddenEdge else { return railFrame }
        guard !railLayoutFrame.isEmpty, !areaBounds.isEmpty else { return .zero }
        return ControlIslandPlacement.flapFrame(for: railLayoutFrame, at: edge, in: areaBounds)
    }

    /// The window side the rail is on, from its saved placement, for light that must pick a
    /// side before the rail has reported a frame.
    var side: ControlIslandPlacement.Edge {
        placement.x > 0.5 ? .right : .left
    }

    /// Work in progress on the controls, which keeps the glass present and the pointer grace alive.
    var isEngaged: Bool {
        isHovered || hasKeyboardFocus || isPresenting || isDragging || showsAddress || showsCustomization
            || isReorderingFavorites || tabInfo.isVisible || isHeldAwake()
    }

    /// Whether a ``holdAwake(for:now:)`` is still running at `now`.
    func isHeldAwake(now: Date = Date()) -> Bool {
        now < awakeUntil
    }

    /// Keeps the controls engaged for `duration` from `now`; a longer hold already running is kept.
    func holdAwake(for duration: TimeInterval, now: Date = Date()) {
        let until = now.addingTimeInterval(duration)
        guard until > awakeUntil else { return }
        awakeUntil = until
        wake()
        awakeHoldTask?.cancel()
        awakeHoldTask = Task(name: "Release browser controls hold") { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            awakeUntil = .distantPast
            awakeHoldTask = nil
        }
    }

    func savePlacement() {
        guard let data = try? JSONEncoder().encode(placement) else { return }
        defaults?.set(data, forKey: Self.placementKey)
    }

    func resetPlacement() {
        placement = .init()
        savePlacement()
    }

    func reportFrame(_ frame: CGRect, for item: ControlIslandItem) {
        guard itemFrames[item] != frame else { return }
        itemFrames[item] = frame
    }

    func clearFrames() {
        railFrame = .zero
        railLayoutFrame = .zero
        itemFrames = [:]
        pageCardFrame = .zero
    }

    func focus() {
        revealAtEdge(.request)
        hasKeyboardFocus = true
        focusRequest &+= 1
    }

    func tracksPointer(_ point: CGPoint, now: Date = Date()) -> ControlIslandHoverPath.Phase {
        lastPointerMovement = now
        let reachedEdge = isHiddenAtEdge && reachesRevealStrip(point)
        if reachedEdge || reachesFlap(point) {
            revealAtEdge(.pointer, now: now)
        }
        let phase = hoverPath.phase(at: point, regions: hitRegions, now: now)
        let reach = isQuiet ? Self.nearDistance : Self.farDistance
        let near = reachedEdge || phase != .outside
            || (companionFrame.isEmpty || isHiddenAtEdge ? hitRegions : hitRegions + [companionFrame]).contains { $0.insetBy(dx: -reach, dy: -reach).contains(point) }
        setQuiet(!near)
        pointerIsNear = near
        if near {
            lastNearPointer = now
            watchForStillness()
        } else {
            scheduleEdgeHide()
        }
        return phase
    }

    /// Whether `point` is on the reveal strip or past it beyond the window's edge: a pointer
    /// that leaves the window across that edge reaches the strip whatever its speed.
    private func reachesRevealStrip(_ point: CGPoint) -> Bool {
        guard let edge = hiddenEdge, !revealStrip.isEmpty, point.y >= revealStrip.minY, point.y <= revealStrip.maxY else { return false }
        return edge == .left ? point.x <= revealStrip.maxX : point.x >= revealStrip.minX
    }

    /// Whether `point` has come to the flap: within reach of the hidden edge, at the strip's
    /// height. The flap always marks a hidden rail, so the rail is found without a search.
    private func reachesFlap(_ point: CGPoint) -> Bool {
        guard isHiddenAtEdge, let edge = hiddenEdge, !areaBounds.isEmpty, !revealStrip.isEmpty,
              point.y >= revealStrip.minY, point.y <= revealStrip.maxY else { return false }
        let edgeX = edge == .left ? areaBounds.minX : areaBounds.maxX
        return abs(point.x - edgeX) <= Self.flapReach
    }

    // MARK: Hiding at the Edge

    /// What brought a hidden rail back on screen.
    enum EdgeReveal {
        /// The pointer reached the window edge.
        case pointer
        /// A shortcut, the lens, the tour, or a drag that needs the rail.
        case request
    }

    func setHidesAtEdge(_ hides: Bool, now: Date = Date()) {
        configuration.setHidesAtEdge(hides)
        isTuckedAway = false
        edgeReveal = nil
        lastNearPointer = now
        scheduleEdgeHide()
    }

    /// Brings a hidden rail back and wakes it; it hides again once the pointer has stayed away.
    func revealAtEdge(_ reveal: EdgeReveal, now: Date = Date()) {
        lastNearPointer = now
        guard hiddenEdge != nil else { return }
        if isTuckedAway {
            isTuckedAway = false
            edgeReveal = reveal
        }
        wake()
        scheduleEdgeHide()
    }

    /// Sends the rail past its window edge, closing the page card and recent list first.
    func hideAtEdge() {
        guard hiddenEdge != nil, !isTuckedAway else { return }
        edgeHideTask?.cancel()
        edgeHideTask = nil
        dismiss(returnsFocusToPage: false)
        isTuckedAway = true
        edgeReveal = nil
    }

    /// Escape on a rail the pointer brought back: it hides at once. Returns whether it hid.
    @discardableResult
    func hideAfterPointerReveal() -> Bool {
        guard edgeReveal == .pointer, !isPresenting, !showsCustomization, !isDragging, !isNeededOnScreen else { return false }
        hideAtEdge()
        return true
    }

    /// Keeps the rail on screen while the tour, the lens, or a drag needs it.
    func setNeededOnScreen(_ needed: Bool) {
        isNeededOnScreen = needed
        if needed {
            revealAtEdge(.request)
        }
    }

    /// Hides the rail once the pointer has been past the wake distance for `stillDelay`, and
    /// nothing on the rail or beyond it needs it.
    private func scheduleEdgeHide() {
        guard edgeHideTask == nil, hiddenEdge != nil, !isTuckedAway else { return }
        edgeHideTask = Task(name: "Hide browser controls at the edge") { [weak self] in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(self?.lastNearPointer ?? .distantPast)
                try? await Task.sleep(for: .seconds(max(0.1, Self.stillDelay - elapsed)))
                guard let self, !Task.isCancelled else { return }
                guard hiddenEdge != nil, !isTuckedAway else {
                    edgeHideTask = nil; return
                }
                if pointerIsNear || isEngaged || isNeededOnScreen || companionIsEngaged {
                    lastNearPointer = Date()
                } else if Date().timeIntervalSince(lastNearPointer) >= Self.stillDelay {
                    edgeHideTask = nil
                    hideAtEdge()
                    return
                }
            }
        }
    }

    /// Rests the controls once the pointer has stayed still for `stillDelay`.
    @discardableResult
    func quietIfStill(now: Date = Date()) -> Bool {
        guard !isQuiet, now.timeIntervalSince(lastPointerMovement) >= Self.stillDelay else { return false }
        setQuiet(true)
        return true
    }

    func wake() {
        setQuiet(false)
        watchForStillness()
    }

    private func setQuiet(_ quiet: Bool) {
        if quiet {
            quietTask?.cancel(); quietTask = nil
        }
        guard isQuiet != quiet else { return }
        isQuiet = quiet
    }

    private func watchForStillness() {
        guard quietTask == nil else { return }
        quietTask = Task(name: "Rest browser controls") { [weak self] in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(self?.lastPointerMovement ?? .distantPast)
                try? await Task.sleep(for: .seconds(max(0.1, Self.stillDelay - elapsed)))
                guard let self, !Task.isCancelled else { return }
                if quietIfStill() {
                    quietTask = nil; return
                }
            }
        }
    }

    func dismissIfOutside(_ point: CGPoint) {
        guard !isPresenting, !tabInfo.isMenuPresented, !showsCustomization, !isDragging, !hitRegions.contains(where: { $0.contains(point) }),
              isHovered || hasKeyboardFocus || showsAddress || tabInfo.isVisible else { return }
        dismiss(returnsFocusToPage: false)
    }

    func dismiss(returnsFocusToPage: Bool = true) {
        isHovered = false
        hasKeyboardFocus = false
        showsAddress = false
        tabInfo.dismiss()
        dismissalRequest &+= 1
        if returnsFocusToPage {
            pageFocusRequest &+= 1
        }
    }
}
