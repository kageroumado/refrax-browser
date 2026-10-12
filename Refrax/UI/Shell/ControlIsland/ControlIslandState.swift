import Foundation
import Observation

/// Per-window disclosure and placement state for the browser controls.
@Observable
final class ControlIslandState {
    enum Mode: String, CaseIterable {
        case marks, rail, button

        var title: String {
            switch self {
            case .marks: "Page and space marks"
            case .rail: "Icon rail"
            case .button: "Single button"
            }
        }
    }

    var placement: ControlIslandPlacement
    var markPlacement = ControlIslandPlacement(x: 0, y: 0)
    var favoritePlacement = ControlIslandPlacement(x: 1, y: 0.15)
    let configuration: ControlIslandConfiguration
    let tabInfo = ControlIslandTabInfoState()
    var showsCustomization = false
    var mode: Mode {
        didSet { defaults?.set(mode.rawValue, forKey: Self.modeKey) }
    }
    var isHovered = false
    var hasKeyboardFocus = false
    var isLatched = false
    var isPresenting = false
    var showsAddress = false
    var isDragging = false
    var isReorderingFavorites = false
    var focusRequest = 0
    var dismissalRequest = 0
    var pageFocusRequest = 0
    private var controlHitRegions: [CGRect] = []
    var favoriteHitRegions: [CGRect] = []
    var hitRegions: [CGRect] {
        get { controlHitRegions + favoriteHitRegions }
        set { controlHitRegions = newValue }
    }

    @ObservationIgnored private let defaults: UserDefaults?
    private static let placementKey = "controlIsland.placement"
    private static let modeKey = "controlIsland.presentation.v3"

    init(defaults: UserDefaults? = .standard, configuration: ControlIslandConfiguration = .shared) {
        self.defaults = defaults
        self.configuration = configuration
        let savedMode = defaults?.string(forKey: Self.modeKey).flatMap(Mode.init(rawValue:))
        self.mode = savedMode == .marks ? .rail : savedMode ?? .rail
        self.placement = defaults?.data(forKey: Self.placementKey)
            .flatMap { try? JSONDecoder().decode(ControlIslandPlacement.self, from: $0) } ?? .init()
    }

    var isRevealed: Bool {
        mode == .rail || isHovered || hasKeyboardFocus || isLatched || isPresenting || isDragging || showsAddress || showsCustomization || tabInfo.isVisible
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

    func dismissIfOutside(_ point: CGPoint) {
        guard !isPresenting, !tabInfo.isMenuPresented, !showsCustomization, !isDragging, !hitRegions.contains(where: { $0.contains(point) }),
              isHovered || hasKeyboardFocus || isLatched || showsAddress || tabInfo.isVisible else { return }
        dismiss(returnsFocusToPage: false)
    }

    func dismiss(returnsFocusToPage: Bool = true) {
        isLatched = false
        isHovered = false
        hasKeyboardFocus = false
        showsAddress = false
        tabInfo.dismiss()
        dismissalRequest &+= 1
        if returnsFocusToPage { pageFocusRequest &+= 1 }
    }
}
