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

    // App menu
    case checkForUpdates = 2_100

    // View menu - sidebar mode
    case sidebarModeOverlay = 3_001
    case sidebarModeCompact = 3_002
}
