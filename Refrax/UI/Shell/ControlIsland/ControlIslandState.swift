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
    /// The pointer is far from the controls or has been still: the glass clears and the glyphs recede.
    private(set) var isQuiet = false
    var focusRequest = 0
    var dismissalRequest = 0
    var pageFocusRequest = 0
    @ObservationIgnored var hitRegions: [CGRect] = []
    @ObservationIgnored var pointerMoved: ((CGPoint) -> Void)?
    @ObservationIgnored var lastPointerMovement = Date.distantPast
    @ObservationIgnored private var hoverPath = ControlIslandHoverPath()
    @ObservationIgnored private var quietTask: Task<Void, Never>?

    @ObservationIgnored private let defaults: UserDefaults?
    private static let placementKey = "controlIsland.placement"

    /// Pointer travel this close to the controls keeps them awake.
    static let nearDistance: CGFloat = 160
    /// A pointer resting past this distance after waking the controls lets them rest again.
    static let farDistance: CGFloat = 220
    static let stillDelay: TimeInterval = 2.5

    init(defaults: UserDefaults? = .standard, configuration: ControlIslandConfiguration = .shared) {
        self.defaults = defaults
        self.configuration = configuration
        self.placement = defaults?.data(forKey: Self.placementKey)
            .flatMap { try? JSONDecoder().decode(ControlIslandPlacement.self, from: $0) } ?? .init()
    }

    /// Work in progress on the controls, which keeps the glass present and the pointer grace alive.
    var isEngaged: Bool {
        isHovered || hasKeyboardFocus || isPresenting || isDragging || showsAddress || showsCustomization
            || isReorderingFavorites || tabInfo.isVisible
    }

    func savePlacement() {
        guard let data = try? JSONEncoder().encode(placement) else { return }
        defaults?.set(data, forKey: Self.placementKey)
    }

    func resetPlacement() {
        placement = .init()
        savePlacement()
    }

    func focus() {
        hasKeyboardFocus = true
        focusRequest &+= 1
    }

    func tracksPointer(_ point: CGPoint, now: Date = Date()) -> ControlIslandHoverPath.Phase {
        lastPointerMovement = now
        let phase = hoverPath.phase(at: point, regions: hitRegions, now: now)
        let reach = isQuiet ? Self.nearDistance : Self.farDistance
        let near = phase != .outside || hitRegions.contains { $0.insetBy(dx: -reach, dy: -reach).contains(point) }
        setQuiet(!near)
        if near { watchForStillness() }
        return phase
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
        if quiet { quietTask?.cancel(); quietTask = nil }
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
                if quietIfStill() { quietTask = nil; return }
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
        if returnsFocusToPage { pageFocusRequest &+= 1 }
    }
}
