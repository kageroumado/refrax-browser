/// Where a menu opens from. Providers read it to decide which of their actions apply.
nonisolated enum MenuSurface: Sendable {
    /// The ⋯ of a floating card on the desk or in Recent.
    case floatingCard
    /// The ⋯ of the current page's card, beside the control rail.
    case pageCard
    /// A tab row in the full sidebar.
    case sidebarRow
    /// A tab button in the compact sidebar.
    case compactRow

    var isCard: Bool {
        switch self {
        case .floatingCard, .pageCard: true
        case .sidebarRow, .compactRow: false
        }
    }
}
