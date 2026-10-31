// MARK: - Menu Item Tags

enum MenuItemTag: Int {
    case browserUndo = 1_001
    case browserRedo = 1_002
    case reopenLastClosedTab = 1_003

    // Window menu - toggles
    case keepOnTop = 2_001
    case showOnAllDesktops = 2_002
    case lockWindowSize = 2_003

    // Window menu - opacity levels
    case opacity100 = 2_010
    case opacity80 = 2_011
    case opacity60 = 2_012
    case opacity40 = 2_013

    /// App menu
    case checkForUpdates = 2_100

    /// View menu - rendering engine
    case switchRenderingEngine = 3_010

    /// View menu - sound
    case muteTab = 3_020

    /// View menu - Favorite Current Page / Remove from Favorites
    case favoriteCurrentPage = 3_030

    /// View menu - Hide / Show Browser Controls (⌘S)
    case browserControlsEdgeHiding = 3_040
}
