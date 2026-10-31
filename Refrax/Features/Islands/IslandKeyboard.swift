import Foundation

/// What holds the window's keyboard focus when a key comes, as the islands weigh it.
nonisolated enum IslandKeyResponder: Equatable, Sendable {
    /// A text field or text view: every key is its own.
    case textInput
    /// The page, or anything else: it keeps every key but the arrows until browsing starts.
    case other
}

/// Whether latched islands take a key, or leave it to the page.
///
/// Browsing starts only with an arrow, or from Command Lens: Return, Delete, Space, Escape,
/// and letters typed into a page stay the page's until then, so a Delete meant for a form
/// never closes its tab. Once started, the islands take every key they answer. Nothing is
/// taken while a text field has focus, or while the library drawer or the centered lens
/// covers the islands.
nonisolated enum IslandKeyRouting {
    static func takes(_ key: IslandKey, browsing: Bool, responder: IslandKeyResponder, covered: Bool) -> Bool {
        guard responder != .textInput, !covered else { return false }
        if browsing {
            return true
        }
        return switch key {
        case .up, .down, .left, .right: true
        case .open, .close, .preview, .leave, .text: false
        }
    }
}

/// A key the islands answer while they have the keyboard.
nonisolated enum IslandKey: Equatable, Sendable {
    case up
    case down
    case left
    case right
    /// Return: opens the chosen row's page.
    case open
    /// Delete or ⌘Delete: closes the chosen row's tab.
    case close
    /// Space: shows the chosen row's page beside its island, or puts it away.
    case preview
    /// Escape: puts the preview away, else leaves the islands.
    case leave
    /// Typed text: chooses the row whose title starts with it.
    case text(String)

    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
    }

    var isText: Bool {
        if case .text = self {
            true
        } else {
            false
        }
    }

    /// The key an event with `keyCode` and `characters` is, or `nil` for one that is not the
    /// islands' (a shortcut, a key under Control or Option), which goes on to the page.
    init?(keyCode: UInt16, characters: String?, command: Bool, control: Bool, option: Bool) {
        if control || option {
            return nil
        }
        if command {
            guard keyCode == KeyCode.delete else { return nil }
            self = .close
            return
        }
        switch keyCode {
        case TableDirection.up.keyCode: self = .up
        case TableDirection.down.keyCode: self = .down
        case TableDirection.left.keyCode: self = .left
        case TableDirection.right.keyCode: self = .right
        case KeyCode.returnKey, KeyCode.enter: self = .open
        case KeyCode.delete, KeyCode.forwardDelete: self = .close
        case KeyCode.space: self = .preview
        case KeyCode.escape: self = .leave
        default:
            guard let characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).contains($0) })
            else { return nil }
            self = .text(characters)
        }
    }
}

/// Moving through the islands' rows with the keyboard alone: a chosen row, apart from the
/// page shown, that the arrows move, Return opens, Delete closes, Space previews, and typing
/// a title jumps to.
///
/// The islands are given as columns of their shown tab rows, in their order on the window;
/// a section's header is never a stop. What lies left or right of an island is the caller's
/// to say, from the islands' places.
nonisolated struct IslandKeyboardNavigator: Equatable, Sendable {
    /// One island's shown tab rows.
    struct Column: Equatable, Sendable {
        let id: UUID
        let tabIDs: [UUID]
    }

    /// What a key asks of the islands.
    enum Effect: Equatable, Sendable {
        /// Nothing to do: the key met an edge, or matched nothing.
        case none
        /// The chosen row moved.
        case moved
        /// Open this tab's page.
        case open(UUID)
        /// Close this tab; the chosen row has moved on to its neighbor.
        case close(UUID)
        /// Show this tab's page beside its island, or put the preview away.
        case preview(UUID?)
        /// Leave the islands.
        case leave
    }

    /// How long typed letters keep adding to one title.
    static let typingPause: TimeInterval = 1

    /// The chosen row.
    private(set) var cursor: UUID?
    /// The page beside its island follows the chosen row.
    private(set) var isPreviewing = false
    /// Where a row was: its island, and its place there.
    private struct Place: Equatable, Sendable {
        let island: UUID
        let index: Int
    }

    /// The chosen row's island and place in it, to come back to when the row goes away.
    private var lastPlace: Place?
    private var typed = ""
    private var typedAt: Date?

    /// Starts on `current`, or the first row of the first island when it is on none.
    init(current: UUID?, columns: [Column]) {
        if let current, columns.contains(where: { $0.tabIDs.contains(current) }) {
            self.cursor = current
        } else {
            self.cursor = columns.first { !$0.tabIDs.isEmpty }?.tabIDs.first
        }
        remember(in: columns)
    }

    /// Answers `key`.
    ///
    /// - Parameters:
    ///   - columns: The islands on screen, each its shown tab rows.
    ///   - neighbor: The island left or right of an island, by their places.
    ///   - title: A tab's title, for typing.
    ///   - now: When the key came, for typing.
    mutating func handle(
        _ key: IslandKey, columns: [Column], neighbor: (UUID, TableDirection) -> UUID?, title: (UUID) -> String, now: Date = .now,
    ) -> Effect {
        if !key.isText {
            typed = ""
            typedAt = nil
        }
        guard let cursor, let column = columns.first(where: { $0.tabIDs.contains(cursor) }),
              let index = column.tabIDs.firstIndex(of: cursor) else {
            return key == .leave ? leave() : .none
        }
        switch key {
        case .up:
            return move(to: index > 0 ? column.tabIDs[index - 1] : nil, columns: columns)
        case .down:
            return move(to: index + 1 < column.tabIDs.count ? column.tabIDs[index + 1] : nil, columns: columns)
        case .left, .right:
            let direction: TableDirection = key == .left ? .left : .right
            guard let next = neighbor(column.id, direction).flatMap({ id in columns.first { $0.id == id } }), !next.tabIDs.isEmpty else {
                return .none
            }
            // Across, the row at the same height, or the island's last.
            return move(to: next.tabIDs[min(index, next.tabIDs.count - 1)], columns: columns)
        case .open:
            return .open(cursor)
        case .close:
            let rest = column.tabIDs.filter { $0 != cursor }
            self.cursor = rest.isEmpty ? nil : rest[min(index, rest.count - 1)]
            remember(in: columns)
            return .close(cursor)
        case .preview:
            isPreviewing.toggle()
            return .preview(isPreviewing ? cursor : nil)
        case .leave:
            return leave()
        case let .text(text):
            return type(text, from: cursor, columns: columns, title: title, now: now)
        }
    }

    /// The rows changed (a tab closed, a filter, a fold): the chosen row stays when it is
    /// still shown, else the row now at its place, else the first row anywhere.
    mutating func sync(_ columns: [Column]) {
        if let cursor, columns.contains(where: { $0.tabIDs.contains(cursor) }) {
            remember(in: columns)
            return
        }
        if let place = lastPlace, let column = columns.first(where: { $0.id == place.island }), !column.tabIDs.isEmpty {
            cursor = column.tabIDs[min(place.index, column.tabIDs.count - 1)]
        } else {
            cursor = columns.first { !$0.tabIDs.isEmpty }?.tabIDs.first
        }
        remember(in: columns)
    }

    private mutating func move(to tabID: UUID?, columns: [Column]) -> Effect {
        guard let tabID else { return .none }
        cursor = tabID
        remember(in: columns)
        return isPreviewing ? .preview(tabID) : .moved
    }

    private mutating func leave() -> Effect {
        if isPreviewing {
            isPreviewing = false
            return .preview(nil)
        }
        cursor = nil
        return .leave
    }

    /// Jumps to the first row, from the chosen one on and around, whose title starts with what
    /// was typed in one breath; a title that only contains it, when none starts with it.
    private mutating func type(_ text: String, from cursor: UUID, columns: [Column], title: (UUID) -> String, now: Date) -> Effect {
        let continues = typedAt.map { now.timeIntervalSince($0) < Self.typingPause } ?? false
        typed = continues ? typed + text : text
        typedAt = now
        let all = columns.flatMap(\.tabIDs)
        guard let start = all.firstIndex(of: cursor) else { return .none }
        // A new word looks past the chosen row; more letters of the same word may keep it.
        let order = Array(all[(continues ? start : start + 1)...] + all[..<(continues ? start : start + 1)])
        let query = typed
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let found = order.first { title($0).range(of: query, options: options.union(.anchored)) != nil }
            ?? order.first { title($0).range(of: query, options: options) != nil }
        guard let found else { return .none }
        return move(to: found, columns: columns)
    }

    private mutating func remember(in columns: [Column]) {
        guard let cursor, let column = columns.first(where: { $0.tabIDs.contains(cursor) }),
              let index = column.tabIDs.firstIndex(of: cursor) else { return }
        lastPlace = Place(island: column.id, index: index)
    }
}
