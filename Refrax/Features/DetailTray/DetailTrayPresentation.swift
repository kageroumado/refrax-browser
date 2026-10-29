/// Starts drawer animations when visibility changes and validates their completions.
nonisolated struct DetailTrayPresentation {
    private var wantsVisible = false
    private var generation: UInt64 = 0

    /// Returns a transition token when the requested visibility changes.
    mutating func transition(toVisible visible: Bool) -> UInt64? {
        guard wantsVisible != visible else { return nil }
        wantsVisible = visible
        generation &+= 1
        return generation
    }

    /// A hide completion applies only to the latest request to close the drawer.
    func canFinishHiding(_ token: UInt64) -> Bool {
        !wantsVisible && token == generation
    }
}
