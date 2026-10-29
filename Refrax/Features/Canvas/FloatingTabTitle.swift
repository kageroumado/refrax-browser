import SwiftUI

/// A floating card's title, which turns into a field on double-click or from Rename…: Return
/// keeps the name, Escape leaves it, and an empty name goes back to the page's title.
struct FloatingTabTitle: View {
    let tab: Tab
    /// The title's weight; an island's current row is the bold one.
    var weight: Font.Weight = .medium
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private enum Layout {
        static let fontSize: CGFloat = 12
    }

    private var isRenaming: Bool {
        canvas.renamingTabID == tab.id
    }

    var body: some View {
        if isRenaming {
            TextField("Tab Name", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: Layout.fontSize, weight: weight))
                .focused($isFocused)
                .onAppear {
                    draft = tab.displayTitle
                    isFocused = true
                }
                .onSubmit(commit)
                .onExitCommand { canvas.renamingTabID = nil }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        commit()
                    }
                }
                .accessibilityLabel("Name of \(tab.displayTitle)")
        } else {
            Text(tab.displayTitle)
                .font(.system(size: Layout.fontSize, weight: weight))
                .lineLimit(1)
                .onTapGesture(count: 2) { canvas.renamingTabID = tab.id }
                .accessibilityAction(named: "Rename") { canvas.renamingTabID = tab.id }
        }
    }

    private func commit() {
        guard isRenaming else { return }
        canvas.renamingTabID = nil
        TabRenaming.apply(draft, to: tab, tabs: tabs)
    }
}

/// The one rule every rename follows: a new name is kept, the current name changes nothing,
/// and an empty name returns the tab to its page's title.
enum TabRenaming {
    static func apply(_ name: String, to tab: Tab, tabs: TabManager) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if tab.customName != nil {
                tabs.clearCustomName(tab)
            }
        } else if trimmed != tab.displayTitle {
            tabs.setCustomName(trimmed, for: tab)
        }
    }
}
