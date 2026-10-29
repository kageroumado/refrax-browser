import Foundation
import Observation

/// Where a drag of files, images, text, or a link is, as the File Island sees it.
enum FileIslandDropPhase: Equatable {
    case none
    /// Over the window: the island shows itself as the place to drop.
    case window
    /// Over the island: it brightens to say it will keep what is dropped.
    case island
}

/// Per-window placement, rest, and drop state for the File Island.
///
/// The island rests and wakes like the Control Island: clear glass while the pointer is far
/// away or still, frosted as it approaches.
@Observable
final class FileIslandState {
    /// Where the island sits once it has been moved; until then it takes the bottom corner
    /// opposite the Control Island.
    var placement: ControlIslandPlacement?
    var isHovered = false
    /// A popover or menu of the island's is open.
    var isPresenting = false
    var isDragging = false
    /// The full lists of downloads and shelf items, from the overflow row or View › Show Downloads.
    var showsAll = false
    var drop = FileIslandDropPhase.none
    /// The pointer is far from the island or has been still: the glass clears and the glyphs recede.
    private(set) var isQuiet = false
    /// The island's frame in window content coordinates while it shows; zero while it is away.
    var frame: CGRect = .zero
    @ObservationIgnored var hitRegions: [CGRect] = []
    /// The drag session started from one of the island's own items, which it does not keep twice.
    @ObservationIgnored var outgoingDragStarted = Date.distantPast
    @ObservationIgnored private var lastPointerMovement = Date.distantPast
    @ObservationIgnored private var hoverPath = ControlIslandHoverPath()
    @ObservationIgnored private var quietTask: Task<Void, Never>?
    private var awakeUntil = Date.distantPast
    @ObservationIgnored private var awakeHoldTask: Task<Void, Never>?

    /// How long the island stays awake after something arrives on it.
    static let arrivalHold: TimeInterval = 2.5

    /// Work in progress on the island, which keeps the glass present.
    var isEngaged: Bool {
        isHovered || isPresenting || isDragging || showsAll || drop != .none || Date() < awakeUntil
    }

    /// Moves the drop phase, touching observers only when it changes: drags update many times a second.
    func setDrop(_ phase: FileIslandDropPhase) {
        guard drop != phase else { return }
        drop = phase
    }

    /// Opens the full lists, waking the island to hold them.
    func showAll() {
        holdAwake(for: Self.arrivalHold)
        showsAll = true
    }

    /// Keeps the island engaged for `duration`; a longer hold already running is kept.
    func holdAwake(for duration: TimeInterval, now: Date = Date()) {
        let until = now.addingTimeInterval(duration)
        guard until > awakeUntil else { return }
        awakeUntil = until
        wake()
        awakeHoldTask?.cancel()
        awakeHoldTask = Task(name: "Release File Island hold") { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            awakeUntil = .distantPast
            awakeHoldTask = nil
        }
    }

    /// Follows the pointer: inside the island it is hovered; near it the island wakes, far away it rests.
    @discardableResult
    func tracksPointer(_ point: CGPoint, now: Date = Date()) -> ControlIslandHoverPath.Phase {
        lastPointerMovement = now
        let phase = hoverPath.phase(at: point, regions: hitRegions, now: now)
        let reach = isQuiet ? ControlIslandState.nearDistance : ControlIslandState.farDistance
        let near = phase != .outside || hitRegions.contains { $0.insetBy(dx: -reach, dy: -reach).contains(point) }
        setQuiet(!near)
        if near {
            watchForStillness()
        }
        isHovered = phase == .inside
        return phase
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
        quietTask = Task(name: "Rest File Island") { [weak self] in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(self?.lastPointerMovement ?? .distantPast)
                try? await Task.sleep(for: .seconds(max(0.1, ControlIslandState.stillDelay - elapsed)))
                guard let self, !Task.isCancelled else { return }
                if Date().timeIntervalSince(lastPointerMovement) >= ControlIslandState.stillDelay {
                    isQuiet = true
                    quietTask = nil
                    return
                }
            }
        }
    }
}
