/// Where a menu opens from. Providers read it to decide which of their actions apply.
nonisolated enum MenuSurface: Sendable {
    /// The ⋯ of a floating card on the desk or in Recent.
    case floatingCard
    /// The ⋯ of the current page's card, beside the control rail.
    case pageCard
}
