import Foundation

// MARK: - URL Policy

/// The URLs a control client may open.
nonisolated enum ControlURLPolicy {
    /// Schemes a client may navigate to or fetch.
    static let allowedSchemes: Set<String> = ["http", "https", "about"]

    enum Refusal: Error, Equatable {
        case invalid(String)
        case scheme(String)
    }

    /// Parses `string` as a URL a client may open. A string with no scheme is read as an
    /// `https` address.
    static func navigableURL(from string: String) throws(Refusal) -> URL {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalid(string) }

        let candidate = URL(string: trimmed).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(string: "https://\(trimmed)")
        guard let url = candidate, let scheme = url.scheme?.lowercased() else {
            throw .invalid(string)
        }
        guard allowedSchemes.contains(scheme) else {
            throw .scheme(scheme)
        }
        if scheme != "about", url.host?.isEmpty ?? true {
            throw .invalid(string)
        }
        return url
    }
}

// MARK: - Space Lock Gate

/// Keeps control clients out of locked spaces: their tabs are invisible, and naming one
/// directly is refused.
struct ControlLockGate {
    /// Whether a space is locked and not currently unlocked.
    let isLocked: (Space) -> Bool

    /// The tabs whose space is unlocked.
    func visibleTabs(_ tabs: [Tab]) -> [Tab] {
        tabs.filter { !isLocked(tab: $0) }
    }

    /// The spaces' tabs, minus those in locked spaces.
    func visibleTabs(in spaces: [Space]) -> [Tab] {
        spaces.filter { !isLocked($0) }.flatMap(\.tabs)
    }

    func ensureUnlocked(_ space: Space) throws(RefraxControlServer.ControlError) {
        if isLocked(space) {
            throw .spaceLocked(space.name)
        }
    }

    func ensureUnlocked(_ tab: Tab) throws(RefraxControlServer.ControlError) {
        if let space = tab.space {
            try ensureUnlocked(space)
        }
    }

    private func isLocked(tab: Tab) -> Bool {
        tab.space.map(isLocked) ?? false
    }
}

// MARK: - Tab Reference Resolution

/// Resolves the tab references `refrax-ctl` accepts. See ``RefraxControlServer`` for the
/// reference forms.
struct ControlTabResolver {
    /// Every tab in every space.
    let allTabs: [Tab]
    /// The tabs of the active window's space, in order.
    let spaceTabs: [Tab]
    let activeTab: Tab?
    let gate: ControlLockGate

    typealias ControlError = RefraxControlServer.ControlError

    func resolve(_ ref: String) throws -> Tab {
        let tab = try find(ref)
        try gate.ensureUnlocked(tab)
        return tab
    }

    private func find(_ ref: String) throws -> Tab {
        // Locked tabs stay out of every search, so a fuzzy match neither lands on one nor
        // names one in an ambiguity error. An exact ID or the active tab still resolves,
        // and `resolve` refuses it as locked.
        let searchable = gate.visibleTabs(allTabs)
        let ordered = gate.visibleTabs(spaceTabs)

        switch ref.lowercased() {
        case "active":
            guard let activeTab else { throw ControlError.noActiveTab }
            return activeTab
        case "first":
            guard let tab = ordered.first else { throw ControlError.noTabs }
            return tab
        case "last":
            guard let tab = ordered.last else { throw ControlError.noTabs }
            return tab
        case "next":
            guard let activeTab else { throw ControlError.noActiveTab }
            guard let index = ordered.firstIndex(where: { $0.id == activeTab.id }), index + 1 < ordered.count else {
                throw ControlError.tabNotFound("next (no tab after active)")
            }
            return ordered[index + 1]
        case "prev", "previous":
            guard let activeTab else { throw ControlError.noActiveTab }
            guard let index = ordered.firstIndex(where: { $0.id == activeTab.id }), index > 0 else {
                throw ControlError.tabNotFound("previous (no tab before active)")
            }
            return ordered[index - 1]
        default:
            break
        }

        if let tab = allTabs.first(where: { ref == "\($0.id)" }) {
            return tab
        }

        // A prefix of the id, as the CLI prints ids; four characters or more, so a short
        // number still reads as an index
        if ref.count >= 4, ref.allSatisfy({ $0.isHexDigit || $0 == "-" }) {
            let prefix = ref.lowercased()
            let byID = searchable.filter { $0.id.uuidString.lowercased().hasPrefix(prefix) }
            if !byID.isEmpty {
                return try uniqueMatch(byID, ref: ref)
            }
        }

        if let index = Int(ref) {
            let zeroIndex = index - 1
            guard zeroIndex >= 0, zeroIndex < ordered.count else {
                throw ControlError.tabNotFound("\(ref) (index out of range, space has \(ordered.count) tabs)")
            }
            return ordered[zeroIndex]
        }

        if ref.lowercased().hasPrefix("title:") {
            let query = String(ref.dropFirst(6))
            return try uniqueMatch(searchable.filter { $0.activePage.title.localizedCaseInsensitiveContains(query) }, ref: ref)
        }

        if ref.lowercased().hasPrefix("url:") {
            let query = String(ref.dropFirst(4))
            return try uniqueMatch(
                searchable.filter { $0.activePage.url.absoluteString.localizedCaseInsensitiveContains(query) },
                ref: ref,
            )
        }

        let matches = searchable.filter {
            $0.activePage.title.localizedCaseInsensitiveContains(ref) ||
                $0.activePage.url.absoluteString.localizedCaseInsensitiveContains(ref)
        }
        return try uniqueMatch(matches, ref: ref)
    }

    private func uniqueMatch(_ matches: [Tab], ref: String) throws -> Tab {
        if matches.count == 1 {
            return matches[0]
        }
        if matches.isEmpty {
            throw ControlError.tabNotFound(ref)
        }
        throw ControlError.ambiguousTabRef(
            ref: ref,
            matches: matches.map { (id: "\($0.id)", title: $0.activePage.title, url: $0.activePage.url.absoluteString) },
        )
    }
}
