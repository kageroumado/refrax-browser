import Foundation

/// Represents the 2x2 grid state during layout editing
struct LayoutGrid {
    private var slots: [PanePosition: TabPage] = [:]
    
    func page(at position: PanePosition) -> TabPage? {
        slots[position]
    }
    
    mutating func setPage(_ page: TabPage, at position: PanePosition) {
        slots[position] = page
    }
    
    mutating func removePage(at position: PanePosition) {
        slots.removeValue(forKey: position)
    }
    
    var filledPositions: [PanePosition] {
        Array(slots.keys)
    }
    
    var allPages: [TabPage] {
        Array(slots.values)
    }
    
    func position(for page: TabPage) -> PanePosition? {
        slots.first(where: { $0.value.id == page.id })?.key
    }
}

typealias GridSlot = PanePosition
