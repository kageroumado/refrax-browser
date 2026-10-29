/// The group a ``MenuAction`` belongs to: its section when inline, its submenu when folded.
///
/// Two groups are the same group when their ``id`` matches. ``rank`` orders groups top to
/// bottom unless the site composing the menu passes its own order.
nonisolated struct MenuGroupID: Hashable, Sendable {
    let id: String
    /// The submenu title when the group folds.
    let title: String
    /// The submenu symbol when the group folds.
    let symbol: String
    let rank: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Rename, Get Info, Preview, Favorite, Mark Unread, Duplicate.
    static let tab = MenuGroupID(id: "tab", title: "Tab", symbol: "rectangle", rank: 0)
    /// Look, Open in New Tab, Open Link in New Window.
    static let open = MenuGroupID(id: "open", title: "Open", symbol: "arrow.up.right.square", rank: 10)
    /// A favorite's Go to Home and Set Current Page as Home, history entries.
    static let go = MenuGroupID(id: "go", title: "Go", symbol: "house", rank: 20)
    static let reload = MenuGroupID(id: "reload", title: "Reload", symbol: "arrow.clockwise", rank: 30)
    /// Mute Tab, Mute Other Tabs.
    static let media = MenuGroupID(id: "media", title: "Sound", symbol: "speaker.wave.2", rank: 35)
    /// Groups, spaces, floating selection.
    static let move = MenuGroupID(id: "move", title: "Move", symbol: "folder", rank: 40)
    /// The tab's slab on the table: its width, a row of its own.
    static let table = MenuGroupID(id: "table", title: "Tab Layout", symbol: "rectangle.split.3x1", rank: 45)
    /// Floating placement: kept visible, compact, region, zoom.
    static let preview = MenuGroupID(id: "preview", title: "Preview", symbol: "rectangle.on.rectangle", rank: 50)
    static let copy = MenuGroupID(id: "copy", title: "Copy", symbol: "doc.on.doc", rank: 60)
    static let share = MenuGroupID(id: "share", title: "Share", symbol: "square.and.arrow.up", rank: 70)
    /// Download, Photos, albums.
    static let save = MenuGroupID(id: "save", title: "Save", symbol: "arrow.down.circle", rank: 80)
    /// yt-dlp and WebKit media controls.
    static let video = MenuGroupID(id: "video", title: "Video", symbol: "film", rank: 90)
    /// Find, Look Up, Translate, Search.
    static let read = MenuGroupID(id: "read", title: "Read", symbol: "text.page", rank: 100)
    /// Emoji & Symbols, Insert GIF, WebKit editing.
    static let edit = MenuGroupID(id: "edit", title: "Edit", symbol: "pencil", rank: 110)
    static let engine = MenuGroupID(id: "engine", title: "Engine", symbol: "engine.combustion", rank: 120)
    static let sort = MenuGroupID(id: "sort", title: "Sort", symbol: "arrow.up.arrow.down", rank: 130)
    static let window = MenuGroupID(id: "window", title: "Window", symbol: "macwindow", rank: 140)
    static let extensions = MenuGroupID(id: "ext", title: "Extensions", symbol: "puzzlepiece.extension", rank: 150)
    /// WebKit items with no mapping.
    static let host = MenuGroupID(id: "host", title: "More", symbol: "ellipsis.circle", rank: 160)
    static let develop = MenuGroupID(id: "develop", title: "Develop", symbol: "hammer", rank: 170)
    /// Always last.
    static let close = MenuGroupID(id: "close", title: "Close", symbol: "xmark", rank: 999)

    /// One group per detected entity, titled with its value ("+33 6 12…", "Oct 14").
    static func detected(_ value: String) -> MenuGroupID {
        MenuGroupID(id: "detect.\(value)", title: value, symbol: "text.magnifyingglass", rank: 95)
    }

    /// One group per sort category, so a Sort submenu keeps its sections.
    static func sort(_ category: String) -> MenuGroupID {
        MenuGroupID(id: "sort.\(category)", title: category, symbol: "arrow.up.arrow.down", rank: 130)
    }
}
