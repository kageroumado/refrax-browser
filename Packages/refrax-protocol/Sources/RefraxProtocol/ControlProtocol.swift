import CoreGraphics
import Foundation

// MARK: - Protocol Version

public enum ControlProtocolVersion: Int, Codable, Sendable {
    case v1 = 1
}

// MARK: - Request

/// A request from the CLI to the Refrax control server.
///
/// Uses a flat JSON format with a `type` discriminator:
/// ```json
/// {"type": "ping"}
/// {"type": "screenshot", "mode": "visible", "tabID": "abc-123"}
/// {"type": "click", "ref": "e5"}
/// ```
public enum ControlRequest: Sendable {
    // Existing
    case ping
    case health
    case state
    case screenshot(ScreenshotParams)
    case pageContent(PageContentParams)
    case click(ClickParams)
    case type(TypeParams)
    case scroll(ScrollParams)
    case navigate(NavigateParams)
    case navigateAndWait(NavigateAndWaitParams)
    case tabList(TabListParams)
    case tabGet(TabGetParams)
    case tabOpen(TabOpenParams)
    case tabClose(TabCloseParams)
    case tabActivate(TabActivateParams)
    case spaceList
    case spaceSwitch(SpaceSwitchParams)
    case windowResize(WindowResizeParams)
    case windowMove(WindowMoveParams)
    case windowCenter
    case windowInfo
    case refPaneShow
    case refPaneHide
    case refPaneToggle
    case hotkey(HotkeyParams)
    case sidebarToggle
    case inspectorToggle
    case commandLens
    case addressLens

    // UI Accessibility Tree
    case uiAXTree(UIAXTreeParams)
    case uiAXClick(UIAXClickParams)

    // Tier 1A: Extended Tab Operations
    case tabPin(TabIDParams)
    case tabDuplicate(TabIDParams)
    case tabRename(TabRenameParams)
    case tabMute(TabIDParams)
    case tabGoBack(OptionalTabIDParams)
    case tabGoForward(OptionalTabIDParams)
    case tabNext
    case tabPrevious
    case tabDetail(OptionalTabIDParams)
    case tabCloseOthers(TabIDParams)
    case tabReopenClosed
    case tabRecentlyClosed
    case tabMoveToSpace(TabMoveToSpaceParams)
    case tabMoveToGroup(TabMoveToGroupParams)
    case tabRemoveFromGroup(TabIDParams)
    case tabMoveToRefPane(TabIDParams)
    case tabReorder(TabReorderParams)
    case tabMarkRead(TabIDParams)
    case tabMarkUnread(TabIDParams)
    case tabCopyURL(TabCopyURLParams)
    case tabReload(TabReloadParams)
    case tabIsLoading(OptionalTabIDParams)
    case tabURL(OptionalTabIDParams)
    case tabWaitLoaded(TabWaitLoadedParams)

    // Tier 1B: Tab Group CRUD
    case groupList(GroupListParams)
    case groupCreate(GroupCreateParams)
    case groupDelete(GroupDeleteParams)
    case groupRename(GroupRenameParams)
    case groupSetColor(GroupSetColorParams)
    case groupSetIcon(GroupSetIconParams)
    case groupToggleCollapsed(GroupToggleCollapsedParams)

    // Tier 1C: Page Operations
    case pageZoomIn(OptionalTabIDParams)
    case pageZoomOut(OptionalTabIDParams)
    case pageZoomReset(OptionalTabIDParams)
    case pageFind(PageFindParams)
    case pageFindNext(OptionalTabIDParams)
    case pageFindPrevious(OptionalTabIDParams)
    case pageFindDismiss(OptionalTabIDParams)
    case pageExecJS(PageExecJSParams)
    case pageSource(OptionalTabIDParams)
    case pageVideoViewer(PageVideoViewerParams)
    case pagePiP(PagePiPParams)

    // Tier 1D: Reference Pane Extended
    case refPaneAddTab(RefPaneAddTabParams)
    case refPaneCloseTab(RefPaneCloseTabParams)
    case refPaneListTabs
    case refPaneActivateTab(RefPaneActivateTabParams)
    case refPaneMoveToMain(RefPaneMoveToMainParams)

    // Tier 1E: Visual Agent Features
    case visualHighlight(VisualHighlightParams)
    case visualCursor(VisualCursorParams)
    case visualClick(VisualClickParams)
    case visualScrollTo(VisualScrollToParams)
    case visualClear

    // Tier 2A: Bookmarks
    case bookmarkList(BookmarkListParams)
    case bookmarkCreate(BookmarkCreateParams)
    case bookmarkDelete(BookmarkDeleteParams)
    case bookmarkFavorite(BookmarkFavoriteParams)
    case bookmarkUnfavorite(BookmarkUnfavoriteParams)
    case bookmarkFolderList
    case bookmarkFolderCreate(BookmarkFolderCreateParams)

    // Tier 2B: History
    case historyList(HistoryListParams)
    case historySearch(HistorySearchParams)
    case historyClear(HistoryClearParams)
    case historyFrequent(HistoryFrequentParams)

    // Tier 2C: Space CRUD
    case spaceCreate(SpaceCreateParams)
    case spaceUpdate(SpaceUpdateParams)
    case spaceDelete(SpaceDeleteParams)

    // Tier 2D: Window Extended
    case windowKeepOnTop
    case windowAllDesktops
    case windowLockSize
    case windowSetOpacity(WindowSetOpacityParams)
    case windowFullScreen
    case windowMinimize

    // Tier 2E: Site Settings
    case siteSettingsGet(SiteSettingsGetParams)
    case siteSettingsSet(SiteSettingsSetParams)

    // Tier 2F: Developer Tools
    case devInspector(DevInspectorParams)
    case devConsole(OptionalTabIDParams)
    case devResources(OptionalTabIDParams)
    case devProfiling(OptionalTabIDParams)
    case devElementSelection(OptionalTabIDParams)
    case devEmptyCaches
    case devConsoleLog(DevConsoleLogParams)
    case devNetworkLog(DevNetworkLogParams)
    case devCookies(DevCookiesParams)
    case devStorage(DevStorageParams)

    // Tier 3: Interaction Enhancements
    case hover(HoverParams)
    case formInput(FormInputParams)

    // Global Settings
    case settingsList(SettingsListParams)
    case settingsGet(SettingsGetParams)
    case settingsSet(SettingsSetParams)

    // MARK: - Compound Commands

    case navigateAndRead(NavigateAndReadParams)
    case clickAndRead(ClickAndReadParams)
    case fillForm(FillFormParams)
    case scrollAndRead(ScrollAndReadParams)
    case findElements(FindElementsParams)

    // MARK: - Program Execution

    case execProgram(ExecProgramParams)
    case resumeProgram(ResumeProgramParams)

    // MARK: - Cookie Consent

    case dismissCookies(DismissCookiesParams)

    // MARK: - Headless Fetch

    /// Loads a URL in a headless WKWebView (no tab created) and returns page content.
    case fetch(FetchParams)

    /// Creates a new tab, navigates to the URL, and optionally waits/returns content.
    case navigateNewTab(NavigateNewTabParams)
}

// MARK: - Request Parameters

public extension ControlRequest {
    // -- Shared param types --

    struct TabIDParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct OptionalTabIDParams: Codable, Sendable {
        public var tabID: String?
        public var pageID: String?

        public init(tabID: String? = nil, pageID: String? = nil) {
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    // -- Existing params --

    struct ScreenshotParams: Codable, Sendable {
        public var mode: ScreenshotMode
        public var tabID: String?
        public var pageID: String?
        public var outputPath: String?
        public var grid: Bool?
        public var logical: Bool?
        /// Region to capture as "x,y,w,h" in document coordinates.
        /// When set, overrides `mode` (except `window`/`window-glass`).
        public var rect: String?

        public enum ScreenshotMode: String, Codable, Sendable {
            case window
            case visible
            case full
            case windowGlass = "window-glass"
        }

        public init(
            mode: ScreenshotMode = .visible,
            tabID: String? = nil,
            pageID: String? = nil,
            outputPath: String? = nil,
            grid: Bool? = nil,
            logical: Bool? = nil,
            rect: String? = nil,
        ) {
            self.mode = mode
            self.tabID = tabID
            self.pageID = pageID
            self.outputPath = outputPath
            self.grid = grid
            self.logical = logical
            self.rect = rect
        }
    }

    struct PageContentParams: Codable, Sendable {
        public var tabID: String?
        public var pageID: String?
        public var scope: Scope

        public enum Scope: String, Codable, Sendable {
            case viewport
            case full
            case html
            case text
            case mainContent
        }

        /// When true, bypass the page content cache and extract fresh content.
        public var fresh: Bool?

        public init(tabID: String? = nil, pageID: String? = nil, scope: Scope = .viewport, fresh: Bool? = nil) {
            self.tabID = tabID
            self.pageID = pageID
            self.scope = scope
            self.fresh = fresh
        }
    }

    struct ClickParams: Codable, Sendable {
        public var ref: String?
        public var x: Double?
        public var y: Double?
        public var doubleClick: Bool?
        public var rightClick: Bool?
        public var modifiers: [String]?
        public var tabID: String?
        public var pageID: String?

        public init(ref: String? = nil, x: Double? = nil, y: Double? = nil, doubleClick: Bool? = nil, rightClick: Bool? = nil, modifiers: [String]? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.ref = ref
            self.x = x
            self.y = y
            self.doubleClick = doubleClick
            self.rightClick = rightClick
            self.modifiers = modifiers
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct TypeParams: Codable, Sendable {
        public var text: String
        public var elementRef: String?
        public var tabID: String?
        public var pageID: String?

        public init(text: String, elementRef: String? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.text = text
            self.elementRef = elementRef
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct ScrollParams: Codable, Sendable {
        public var direction: String?
        public var amount: Int?
        public var ref: String?
        public var tabID: String?
        public var pageID: String?

        public init(direction: String? = nil, amount: Int? = nil, ref: String? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.direction = direction
            self.amount = amount
            self.ref = ref
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct NavigateParams: Codable, Sendable {
        public var url: String
        public var tabID: String?
        public var pageID: String?

        public init(url: String, tabID: String? = nil, pageID: String? = nil) {
            self.url = url
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct NavigateAndWaitParams: Codable, Sendable {
        public var url: String
        public var tabID: String?
        public var pageID: String?
        public var timeout: Int?

        public init(url: String, tabID: String? = nil, pageID: String? = nil, timeout: Int? = nil) {
            self.url = url
            self.tabID = tabID
            self.pageID = pageID
            self.timeout = timeout
        }
    }

    struct TabWaitLoadedParams: Codable, Sendable {
        public var tabID: String?
        public var pageID: String?
        public var timeout: Int?

        public init(tabID: String? = nil, pageID: String? = nil, timeout: Int? = nil) {
            self.tabID = tabID
            self.pageID = pageID
            self.timeout = timeout
        }
    }

    struct TabListParams: Codable, Sendable {
        public var spaceID: String?

        public init(spaceID: String? = nil) {
            self.spaceID = spaceID
        }
    }

    struct TabGetParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct TabOpenParams: Codable, Sendable {
        public var url: String
        public var spaceID: String?
        public var activate: Bool?

        public init(url: String, spaceID: String? = nil, activate: Bool? = nil) {
            self.url = url
            self.spaceID = spaceID
            self.activate = activate
        }
    }

    struct TabCloseParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct TabActivateParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct SpaceSwitchParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct WindowResizeParams: Codable, Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    struct WindowMoveParams: Codable, Sendable {
        public var x: Int
        public var y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    struct HotkeyParams: Codable, Sendable {
        public var keys: String

        public init(keys: String) {
            self.keys = keys
        }
    }

    // -- UI Accessibility Tree params --

    struct UIAXTreeParams: Codable, Sendable {
        public var depth: Int?
        public var id: String?

        public init(depth: Int? = nil, id: String? = nil) {
            self.depth = depth
            self.id = id
        }
    }

    struct UIAXClickParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    // -- Tier 1A: Extended Tab params --

    struct TabRenameParams: Codable, Sendable {
        public var id: String
        public var name: String?

        public init(id: String, name: String? = nil) {
            self.id = id
            self.name = name
        }
    }

    struct TabMoveToSpaceParams: Codable, Sendable {
        public var id: String
        public var spaceID: String

        public init(id: String, spaceID: String) {
            self.id = id
            self.spaceID = spaceID
        }
    }

    struct TabMoveToGroupParams: Codable, Sendable {
        public var id: String
        public var groupID: String

        public init(id: String, groupID: String) {
            self.id = id
            self.groupID = groupID
        }
    }

    struct TabReorderParams: Codable, Sendable {
        public var id: String
        public var index: Int

        public init(id: String, index: Int) {
            self.id = id
            self.index = index
        }
    }

    struct TabCopyURLParams: Codable, Sendable {
        public var id: String
        public var markdown: Bool?

        public init(id: String, markdown: Bool? = nil) {
            self.id = id
            self.markdown = markdown
        }
    }

    struct TabReloadParams: Codable, Sendable {
        public var tabID: String?
        public var pageID: String?
        public var fromOrigin: Bool?

        public init(tabID: String? = nil, pageID: String? = nil, fromOrigin: Bool? = nil) {
            self.tabID = tabID
            self.pageID = pageID
            self.fromOrigin = fromOrigin
        }
    }

    // -- Tier 1B: Group params --

    struct GroupListParams: Codable, Sendable {
        public var spaceID: String?

        public init(spaceID: String? = nil) {
            self.spaceID = spaceID
        }
    }

    struct GroupCreateParams: Codable, Sendable {
        public var name: String
        public var color: String?
        public var icon: String?
        public var spaceID: String?

        public init(name: String, color: String? = nil, icon: String? = nil, spaceID: String? = nil) {
            self.name = name
            self.color = color
            self.icon = icon
            self.spaceID = spaceID
        }
    }

    struct GroupDeleteParams: Codable, Sendable {
        public var id: String
        public var closeTabs: Bool?

        public init(id: String, closeTabs: Bool? = nil) {
            self.id = id
            self.closeTabs = closeTabs
        }
    }

    struct GroupRenameParams: Codable, Sendable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    struct GroupSetColorParams: Codable, Sendable {
        public var id: String
        public var color: String

        public init(id: String, color: String) {
            self.id = id
            self.color = color
        }
    }

    struct GroupSetIconParams: Codable, Sendable {
        public var id: String
        public var icon: String

        public init(id: String, icon: String) {
            self.id = id
            self.icon = icon
        }
    }

    struct GroupToggleCollapsedParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    // -- Tier 1C: Page params --

    struct PageFindParams: Codable, Sendable {
        public var query: String
        public var tabID: String?
        public var pageID: String?

        public init(query: String, tabID: String? = nil, pageID: String? = nil) {
            self.query = query
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct PageExecJSParams: Codable, Sendable {
        public var script: String
        public var tabID: String?
        public var pageID: String?
        /// Evaluate without synthesizing a user gesture. Preserves the page's
        /// transient user activation (gesture-forced evaluation strips it).
        public var noGesture: Bool?

        public init(script: String, tabID: String? = nil, pageID: String? = nil, noGesture: Bool? = nil) {
            self.script = script
            self.tabID = tabID
            self.pageID = pageID
            self.noGesture = noGesture
        }
    }

    struct PageVideoViewerParams: Codable, Sendable {
        public enum Action: String, Codable, Sendable {
            case enter
            case exit
            case toggle
            case status
        }

        public var action: Action
        public var tabID: String?
        public var pageID: String?

        public init(action: Action, tabID: String? = nil, pageID: String? = nil) {
            self.action = action
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct PagePiPParams: Codable, Sendable {
        public enum Action: String, Codable, Sendable {
            case enter
            case exit
            case toggle
            case status
        }

        public var action: Action
        public var tabID: String?
        public var pageID: String?

        public init(action: Action, tabID: String? = nil, pageID: String? = nil) {
            self.action = action
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    // -- Tier 1D: Reference Pane params --

    struct RefPaneAddTabParams: Codable, Sendable {
        public var url: String
        public var title: String?

        public init(url: String, title: String? = nil) {
            self.url = url
            self.title = title
        }
    }

    struct RefPaneCloseTabParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct RefPaneActivateTabParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct RefPaneMoveToMainParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    // -- Tier 1E: Visual params --

    struct VisualHighlightParams: Codable, Sendable {
        public var ref: String
        public var style: String?

        public init(ref: String, style: String? = nil) {
            self.ref = ref
            self.style = style
        }
    }

    struct VisualCursorParams: Codable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    struct VisualClickParams: Codable, Sendable {
        public var ref: String

        public init(ref: String) {
            self.ref = ref
        }
    }

    struct VisualScrollToParams: Codable, Sendable {
        public var ref: String?
        public var y: Double?

        public init(ref: String? = nil, y: Double? = nil) {
            self.ref = ref
            self.y = y
        }
    }

    // -- Tier 2A: Bookmark params --

    struct BookmarkListParams: Codable, Sendable {
        public var folderID: String?
        public var query: String?

        public init(folderID: String? = nil, query: String? = nil) {
            self.folderID = folderID
            self.query = query
        }
    }

    struct BookmarkCreateParams: Codable, Sendable {
        public var url: String
        public var title: String?
        public var folderID: String?
        public var favorite: Bool?

        public init(url: String, title: String? = nil, folderID: String? = nil, favorite: Bool? = nil) {
            self.url = url
            self.title = title
            self.folderID = folderID
            self.favorite = favorite
        }
    }

    struct BookmarkDeleteParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct BookmarkFavoriteParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct BookmarkUnfavoriteParams: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    struct BookmarkFolderCreateParams: Codable, Sendable {
        public var name: String
        public var parentID: String?

        public init(name: String, parentID: String? = nil) {
            self.name = name
            self.parentID = parentID
        }
    }

    // -- Tier 2B: History params --

    struct HistoryListParams: Codable, Sendable {
        public var limit: Int?
        public var domain: String?

        public init(limit: Int? = nil, domain: String? = nil) {
            self.limit = limit
            self.domain = domain
        }
    }

    struct HistorySearchParams: Codable, Sendable {
        public var query: String
        public var limit: Int?

        public init(query: String, limit: Int? = nil) {
            self.query = query
            self.limit = limit
        }
    }

    struct HistoryClearParams: Codable, Sendable {
        public var domain: String?

        public init(domain: String? = nil) {
            self.domain = domain
        }
    }

    struct HistoryFrequentParams: Codable, Sendable {
        public var limit: Int?

        public init(limit: Int? = nil) {
            self.limit = limit
        }
    }

    // -- Tier 2C: Space CRUD params --

    struct SpaceCreateParams: Codable, Sendable {
        public var name: String
        public var color: String?
        public var icon: String?

        public init(name: String, color: String? = nil, icon: String? = nil) {
            self.name = name
            self.color = color
            self.icon = icon
        }
    }

    struct SpaceUpdateParams: Codable, Sendable {
        public var id: String
        public var name: String?
        public var color: String?

        public init(id: String, name: String? = nil, color: String? = nil) {
            self.id = id
            self.name = name
            self.color = color
        }
    }

    struct SpaceDeleteParams: Codable, Sendable {
        public var id: String
        public var moveTabsTo: String?

        public init(id: String, moveTabsTo: String? = nil) {
            self.id = id
            self.moveTabsTo = moveTabsTo
        }
    }

    // -- Tier 2D: Window params --

    struct WindowSetOpacityParams: Codable, Sendable {
        public var percent: Int

        public init(percent: Int) {
            self.percent = percent
        }
    }

    // -- Tier 2E: Site Settings params --

    struct SiteSettingsGetParams: Codable, Sendable {
        public var domain: String

        public init(domain: String) {
            self.domain = domain
        }
    }

    struct SiteSettingsSetParams: Codable, Sendable {
        public var domain: String
        public var zoom: Int?
        public var javascript: Bool?
        public var contentBlockers: Bool?

        public init(domain: String, zoom: Int? = nil, javascript: Bool? = nil, contentBlockers: Bool? = nil) {
            self.domain = domain
            self.zoom = zoom
            self.javascript = javascript
            self.contentBlockers = contentBlockers
        }
    }

    // -- Tier 2F: Developer Tools params --

    struct DevInspectorParams: Codable, Sendable {
        public var action: String?
        public var side: String?
        public var tabID: String?
        public var pageID: String?

        public init(action: String? = nil, side: String? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.action = action
            self.side = side
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct DevConsoleLogParams: Codable, Sendable {
        public var action: String?
        public var tabID: String?
        public var pageID: String?

        public init(action: String? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.action = action
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct DevNetworkLogParams: Codable, Sendable {
        public var action: String?
        public var tabID: String?
        public var pageID: String?

        public init(action: String? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.action = action
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct DevCookiesParams: Codable, Sendable {
        public var domain: String?
        public var tabID: String?
        public var pageID: String?

        public init(domain: String? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.domain = domain
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct DevStorageParams: Codable, Sendable {
        public var action: String?
        public var storageType: String?
        public var key: String?
        public var value: String?
        public var tabID: String?
        public var pageID: String?

        public init(action: String? = nil, storageType: String? = nil, key: String? = nil, value: String? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.action = action
            self.storageType = storageType
            self.key = key
            self.value = value
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    // -- Tier 3: Interaction Enhancement params --

    struct HoverParams: Codable, Sendable {
        public var ref: String?
        public var x: Double?
        public var y: Double?
        public var tabID: String?
        public var pageID: String?

        public init(ref: String? = nil, x: Double? = nil, y: Double? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.ref = ref
            self.x = x
            self.y = y
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct FormInputParams: Codable, Sendable {
        public var ref: String
        public var value: String
        public var tabID: String?
        public var pageID: String?

        public init(ref: String, value: String, tabID: String? = nil, pageID: String? = nil) {
            self.ref = ref
            self.value = value
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    // -- Global Settings params --

    struct SettingsListParams: Codable, Sendable {
        public var category: String?

        public init(category: String? = nil) {
            self.category = category
        }
    }

    struct SettingsGetParams: Codable, Sendable {
        public var key: String

        public init(key: String) {
            self.key = key
        }
    }

    struct SettingsSetParams: Codable, Sendable {
        public var key: String
        public var value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    // -- Compound Command params --

    struct NavigateAndReadParams: Codable, Sendable {
        public let url: String
        public let scope: PageContentParams.Scope?
        public let timeout: Int?
        public let tabID: String?
        public let pageID: String?

        public init(url: String, scope: PageContentParams.Scope? = nil, timeout: Int? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.url = url
            self.scope = scope
            self.timeout = timeout
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct ClickAndReadParams: Codable, Sendable {
        public let ref: String?
        public let fuzzyText: String?
        public let x: Double?
        public let y: Double?
        public let scope: PageContentParams.Scope?
        public let waitForNavigation: Bool?
        public let timeout: Int?
        public let tabID: String?
        public let pageID: String?

        public init(ref: String? = nil, fuzzyText: String? = nil, x: Double? = nil, y: Double? = nil, scope: PageContentParams.Scope? = nil, waitForNavigation: Bool? = nil, timeout: Int? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.ref = ref
            self.fuzzyText = fuzzyText
            self.x = x
            self.y = y
            self.scope = scope
            self.waitForNavigation = waitForNavigation
            self.timeout = timeout
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct FillFormParams: Codable, Sendable {
        public struct FieldEntry: Codable, Sendable {
            public let ref: String
            public let value: String
            public init(ref: String, value: String) {
                self.ref = ref
                self.value = value
            }
        }

        public let fields: [FieldEntry]
        public let submitRef: String?
        public let tabID: String?
        public let pageID: String?

        public init(fields: [FieldEntry], submitRef: String? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.fields = fields
            self.submitRef = submitRef
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct ScrollAndReadParams: Codable, Sendable {
        public let direction: String?
        public let amount: Int?
        public let ref: String?
        public let scope: PageContentParams.Scope?
        public let tabID: String?
        public let pageID: String?

        public init(direction: String? = nil, amount: Int? = nil, ref: String? = nil, scope: PageContentParams.Scope? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.direction = direction
            self.amount = amount
            self.ref = ref
            self.scope = scope
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    struct FindElementsParams: Codable, Sendable {
        public let text: String?
        public let role: String?
        public let tag: String?
        public let limit: Int?
        public let tabID: String?
        public let pageID: String?

        public init(text: String? = nil, role: String? = nil, tag: String? = nil, limit: Int? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.text = text
            self.role = role
            self.tag = tag
            self.limit = limit
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    // -- Program Execution params --

    struct ExecProgramParams: Codable, Sendable {
        public let program: String
        public let timeout: Int?
        public let verbose: Bool?
        public let dryRun: Bool?
        public let tabID: String?
        public let pageID: String?
        public let policy: ProgramSecurityPolicy?

        public init(
            program: String,
            timeout: Int? = nil,
            verbose: Bool? = nil,
            dryRun: Bool? = nil,
            tabID: String? = nil,
            pageID: String? = nil,
            policy: ProgramSecurityPolicy? = nil,
        ) {
            self.program = program
            self.timeout = timeout
            self.verbose = verbose
            self.dryRun = dryRun
            self.tabID = tabID
            self.pageID = pageID
            self.policy = policy
        }
    }

    struct ResumeProgramParams: Codable, Sendable {
        public let token: String

        public init(token: String) {
            self.token = token
        }
    }

    struct DismissCookiesParams: Codable, Sendable {
        /// When true, accept all cookies instead of rejecting non-essential ones.
        public var acceptAll: Bool?
        public var tabID: String?
        public var pageID: String?

        public init(acceptAll: Bool? = nil, tabID: String? = nil, pageID: String? = nil) {
            self.acceptAll = acceptAll
            self.tabID = tabID
            self.pageID = pageID
        }
    }

    // -- Headless Fetch params --

    struct FetchParams: Codable, Sendable {
        public let url: String
        public let scope: PageContentParams.Scope?
        public let timeout: Int?

        public init(url: String, scope: PageContentParams.Scope? = nil, timeout: Int? = nil) {
            self.url = url
            self.scope = scope
            self.timeout = timeout
        }
    }

    struct NavigateNewTabParams: Codable, Sendable {
        public let url: String
        public let scope: PageContentParams.Scope?
        public let timeout: Int?
        public let activate: Bool?
        public let wait: Bool?
        public let spaceID: String?

        public init(
            url: String,
            scope: PageContentParams.Scope? = nil,
            timeout: Int? = nil,
            activate: Bool? = nil,
            wait: Bool? = nil,
            spaceID: String? = nil
        ) {
            self.url = url
            self.scope = scope
            self.timeout = timeout
            self.activate = activate
            self.wait = wait
            self.spaceID = spaceID
        }
    }
}

// MARK: - Program Security Policy

/// Security policy governing what a browser automation program may do.
///
/// Applied before and during execution to prevent abuse:
/// - Static analysis rejects programs exceeding limits pre-execution
/// - Runtime counters enforce limits during execution
public struct ProgramSecurityPolicy: Codable, Sendable {
    /// Domains the program may navigate to. nil = unrestricted.
    public var allowedDomains: [String]?

    /// Domains the program may NOT navigate to.
    public var blockedDomains: [String]?

    /// Max navigation commands per execution.
    public var maxNavigations: Int

    /// Max click/type/fill/hover interactions per execution.
    public var maxInteractions: Int

    /// Max page read operations per execution.
    public var maxPageReads: Int

    /// Max iterations per loop.
    public var maxLoopIterations: Int

    /// Whether page exec (JavaScript) is permitted.
    public var allowJavaScript: Bool

    /// Hard timeout for entire program (seconds).
    public var maxExecutionTime: TimeInterval

    /// How to handle sensitive form fields (password, credit card, SSN).
    public var sensitiveFieldPolicy: SensitiveFieldPolicy

    public enum SensitiveFieldPolicy: String, Codable, Sendable {
        case block
        case requireConfirmation
        case allow
    }

    public init(
        allowedDomains: [String]? = nil,
        blockedDomains: [String]? = nil,
        maxNavigations: Int = 10,
        maxInteractions: Int = 50,
        maxPageReads: Int = 20,
        maxLoopIterations: Int = 100,
        allowJavaScript: Bool = false,
        maxExecutionTime: TimeInterval = 60,
        sensitiveFieldPolicy: SensitiveFieldPolicy = .requireConfirmation,
    ) {
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.maxNavigations = maxNavigations
        self.maxInteractions = maxInteractions
        self.maxPageReads = maxPageReads
        self.maxLoopIterations = maxLoopIterations
        self.allowJavaScript = allowJavaScript
        self.maxExecutionTime = maxExecutionTime
        self.sensitiveFieldPolicy = sensitiveFieldPolicy
    }

    /// Default permissive policy for trusted contexts.
    public static let permissive = ProgramSecurityPolicy(
        allowedDomains: nil,
        blockedDomains: nil,
        maxNavigations: 100,
        maxInteractions: 500,
        maxPageReads: 200,
        maxLoopIterations: 100,
        allowJavaScript: true,
        maxExecutionTime: 300,
        sensitiveFieldPolicy: .allow,
    )

    /// Default restrictive policy for untrusted programs.
    public static let `default` = ProgramSecurityPolicy()
}

// MARK: - Request Codable

extension ControlRequest: Codable {
    private enum TypeKey: String, Codable {
        // Existing
        case ping
        case health
        case state
        case screenshot
        case pageContent
        case click
        case type
        case scroll
        case navigate
        case navigateAndWait
        case tabList
        case tabGet
        case tabOpen
        case tabClose
        case tabActivate
        case spaceList
        case spaceSwitch
        case windowResize
        case windowMove
        case windowCenter
        case windowInfo
        case refPaneShow
        case refPaneHide
        case refPaneToggle
        case hotkey
        case sidebarToggle
        case inspectorToggle
        case commandLens
        case addressLens

        // UI Accessibility Tree
        case uiAXTree
        case uiAXClick

        // Tier 1A
        case tabPin
        case tabDuplicate
        case tabRename
        case tabMute
        case tabGoBack
        case tabGoForward
        case tabNext
        case tabPrevious
        case tabDetail
        case tabCloseOthers
        case tabReopenClosed
        case tabRecentlyClosed
        case tabMoveToSpace
        case tabMoveToGroup
        case tabRemoveFromGroup
        case tabMoveToRefPane
        case tabReorder
        case tabMarkRead
        case tabMarkUnread
        case tabCopyURL
        case tabReload
        case tabIsLoading
        case tabURL
        case tabWaitLoaded

        // Tier 1B
        case groupList
        case groupCreate
        case groupDelete
        case groupRename
        case groupSetColor
        case groupSetIcon
        case groupToggleCollapsed

        // Tier 1C
        case pageZoomIn
        case pageZoomOut
        case pageZoomReset
        case pageFind
        case pageFindNext
        case pageFindPrevious
        case pageFindDismiss
        case pageExecJS
        case pageSource
        case pageVideoViewer
        case pagePiP

        // Tier 1D
        case refPaneAddTab
        case refPaneCloseTab
        case refPaneListTabs
        case refPaneActivateTab
        case refPaneMoveToMain

        // Tier 1E
        case visualHighlight
        case visualCursor
        case visualClick
        case visualScrollTo
        case visualClear

        // Tier 2A
        case bookmarkList
        case bookmarkCreate
        case bookmarkDelete
        case bookmarkFavorite
        case bookmarkUnfavorite
        case bookmarkFolderList
        case bookmarkFolderCreate

        // Tier 2B
        case historyList
        case historySearch
        case historyClear
        case historyFrequent

        // Tier 2C
        case spaceCreate
        case spaceUpdate
        case spaceDelete

        // Tier 2D
        case windowKeepOnTop
        case windowAllDesktops
        case windowLockSize
        case windowSetOpacity
        case windowFullScreen
        case windowMinimize

        // Tier 2E
        case siteSettingsGet
        case siteSettingsSet

        // Tier 2F
        case devInspector
        case devConsole
        case devResources
        case devProfiling
        case devElementSelection
        case devEmptyCaches
        case devConsoleLog
        case devNetworkLog
        case devCookies
        case devStorage

        // Tier 3
        case hover
        case formInput

        // Global Settings
        case settingsList
        case settingsGet
        case settingsSet

        // Compound Commands
        case navigateAndRead
        case clickAndRead
        case fillForm
        case scrollAndRead
        case findElements

        /// Program Execution
        case execProgram = "exec_program"
        case resumeProgram = "resume_program"

        /// Cookie Consent
        case dismissCookies = "dismiss_cookies"

        /// Headless Fetch
        case fetch
        case navigateNewTab
    }

    private struct TypeContainer: Decodable {
        let type: TypeKey

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawValue = try container.decode(String.self, forKey: .type)
            guard let key = TypeKey(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown request type '\(rawValue)'. CLI and server protocol versions may differ — update refrax-ctl.",
                )
            }
            self.type = key
        }

        private enum CodingKeys: String, CodingKey {
            case type
        }
    }

    public init(from decoder: any Decoder) throws {
        let typeContainer = try TypeContainer(from: decoder)

        switch typeContainer.type {
        // Existing
        case .ping: self = .ping
        case .health: self = .health
        case .state: self = .state
        case .screenshot: self = try .screenshot(ScreenshotParams(from: decoder))
        case .pageContent: self = try .pageContent(PageContentParams(from: decoder))
        case .click: self = try .click(ClickParams(from: decoder))
        case .type: self = try .type(TypeParams(from: decoder))
        case .scroll: self = try .scroll(ScrollParams(from: decoder))
        case .navigate: self = try .navigate(NavigateParams(from: decoder))
        case .navigateAndWait: self = try .navigateAndWait(NavigateAndWaitParams(from: decoder))
        case .tabList: self = try .tabList(TabListParams(from: decoder))
        case .tabGet: self = try .tabGet(TabGetParams(from: decoder))
        case .tabOpen: self = try .tabOpen(TabOpenParams(from: decoder))
        case .tabClose: self = try .tabClose(TabCloseParams(from: decoder))
        case .tabActivate: self = try .tabActivate(TabActivateParams(from: decoder))
        case .spaceList: self = .spaceList
        case .spaceSwitch: self = try .spaceSwitch(SpaceSwitchParams(from: decoder))
        case .windowResize: self = try .windowResize(WindowResizeParams(from: decoder))
        case .windowMove: self = try .windowMove(WindowMoveParams(from: decoder))
        case .windowCenter: self = .windowCenter
        case .windowInfo: self = .windowInfo
        case .refPaneShow: self = .refPaneShow
        case .refPaneHide: self = .refPaneHide
        case .refPaneToggle: self = .refPaneToggle
        case .hotkey: self = try .hotkey(HotkeyParams(from: decoder))
        case .sidebarToggle: self = .sidebarToggle
        case .inspectorToggle: self = .inspectorToggle
        case .commandLens: self = .commandLens
        case .addressLens: self = .addressLens
        // UI Accessibility Tree
        case .uiAXTree: self = try .uiAXTree(UIAXTreeParams(from: decoder))
        case .uiAXClick: self = try .uiAXClick(UIAXClickParams(from: decoder))
        // Tier 1A
        case .tabPin: self = try .tabPin(TabIDParams(from: decoder))
        case .tabDuplicate: self = try .tabDuplicate(TabIDParams(from: decoder))
        case .tabRename: self = try .tabRename(TabRenameParams(from: decoder))
        case .tabMute: self = try .tabMute(TabIDParams(from: decoder))
        case .tabGoBack: self = try .tabGoBack(OptionalTabIDParams(from: decoder))
        case .tabGoForward: self = try .tabGoForward(OptionalTabIDParams(from: decoder))
        case .tabNext: self = .tabNext
        case .tabPrevious: self = .tabPrevious
        case .tabDetail: self = try .tabDetail(OptionalTabIDParams(from: decoder))
        case .tabCloseOthers: self = try .tabCloseOthers(TabIDParams(from: decoder))
        case .tabReopenClosed: self = .tabReopenClosed
        case .tabRecentlyClosed: self = .tabRecentlyClosed
        case .tabMoveToSpace: self = try .tabMoveToSpace(TabMoveToSpaceParams(from: decoder))
        case .tabMoveToGroup: self = try .tabMoveToGroup(TabMoveToGroupParams(from: decoder))
        case .tabRemoveFromGroup: self = try .tabRemoveFromGroup(TabIDParams(from: decoder))
        case .tabMoveToRefPane: self = try .tabMoveToRefPane(TabIDParams(from: decoder))
        case .tabReorder: self = try .tabReorder(TabReorderParams(from: decoder))
        case .tabMarkRead: self = try .tabMarkRead(TabIDParams(from: decoder))
        case .tabMarkUnread: self = try .tabMarkUnread(TabIDParams(from: decoder))
        case .tabCopyURL: self = try .tabCopyURL(TabCopyURLParams(from: decoder))
        case .tabReload: self = try .tabReload(TabReloadParams(from: decoder))
        case .tabIsLoading: self = try .tabIsLoading(OptionalTabIDParams(from: decoder))
        case .tabURL: self = try .tabURL(OptionalTabIDParams(from: decoder))
        case .tabWaitLoaded: self = try .tabWaitLoaded(TabWaitLoadedParams(from: decoder))
        // Tier 1B
        case .groupList: self = try .groupList(GroupListParams(from: decoder))
        case .groupCreate: self = try .groupCreate(GroupCreateParams(from: decoder))
        case .groupDelete: self = try .groupDelete(GroupDeleteParams(from: decoder))
        case .groupRename: self = try .groupRename(GroupRenameParams(from: decoder))
        case .groupSetColor: self = try .groupSetColor(GroupSetColorParams(from: decoder))
        case .groupSetIcon: self = try .groupSetIcon(GroupSetIconParams(from: decoder))
        case .groupToggleCollapsed: self = try .groupToggleCollapsed(GroupToggleCollapsedParams(from: decoder))
        // Tier 1C
        case .pageZoomIn: self = try .pageZoomIn(OptionalTabIDParams(from: decoder))
        case .pageZoomOut: self = try .pageZoomOut(OptionalTabIDParams(from: decoder))
        case .pageZoomReset: self = try .pageZoomReset(OptionalTabIDParams(from: decoder))
        case .pageFind: self = try .pageFind(PageFindParams(from: decoder))
        case .pageFindNext: self = try .pageFindNext(OptionalTabIDParams(from: decoder))
        case .pageFindPrevious: self = try .pageFindPrevious(OptionalTabIDParams(from: decoder))
        case .pageFindDismiss: self = try .pageFindDismiss(OptionalTabIDParams(from: decoder))
        case .pageExecJS: self = try .pageExecJS(PageExecJSParams(from: decoder))
        case .pageSource: self = try .pageSource(OptionalTabIDParams(from: decoder))
        case .pageVideoViewer: self = try .pageVideoViewer(PageVideoViewerParams(from: decoder))
        case .pagePiP: self = try .pagePiP(PagePiPParams(from: decoder))
        // Tier 1D
        case .refPaneAddTab: self = try .refPaneAddTab(RefPaneAddTabParams(from: decoder))
        case .refPaneCloseTab: self = try .refPaneCloseTab(RefPaneCloseTabParams(from: decoder))
        case .refPaneListTabs: self = .refPaneListTabs
        case .refPaneActivateTab: self = try .refPaneActivateTab(RefPaneActivateTabParams(from: decoder))
        case .refPaneMoveToMain: self = try .refPaneMoveToMain(RefPaneMoveToMainParams(from: decoder))
        // Tier 1E
        case .visualHighlight: self = try .visualHighlight(VisualHighlightParams(from: decoder))
        case .visualCursor: self = try .visualCursor(VisualCursorParams(from: decoder))
        case .visualClick: self = try .visualClick(VisualClickParams(from: decoder))
        case .visualScrollTo: self = try .visualScrollTo(VisualScrollToParams(from: decoder))
        case .visualClear: self = .visualClear
        // Tier 2A
        case .bookmarkList: self = try .bookmarkList(BookmarkListParams(from: decoder))
        case .bookmarkCreate: self = try .bookmarkCreate(BookmarkCreateParams(from: decoder))
        case .bookmarkDelete: self = try .bookmarkDelete(BookmarkDeleteParams(from: decoder))
        case .bookmarkFavorite: self = try .bookmarkFavorite(BookmarkFavoriteParams(from: decoder))
        case .bookmarkUnfavorite: self = try .bookmarkUnfavorite(BookmarkUnfavoriteParams(from: decoder))
        case .bookmarkFolderList: self = .bookmarkFolderList
        case .bookmarkFolderCreate: self = try .bookmarkFolderCreate(BookmarkFolderCreateParams(from: decoder))
        // Tier 2B
        case .historyList: self = try .historyList(HistoryListParams(from: decoder))
        case .historySearch: self = try .historySearch(HistorySearchParams(from: decoder))
        case .historyClear: self = try .historyClear(HistoryClearParams(from: decoder))
        case .historyFrequent: self = try .historyFrequent(HistoryFrequentParams(from: decoder))
        // Tier 2C
        case .spaceCreate: self = try .spaceCreate(SpaceCreateParams(from: decoder))
        case .spaceUpdate: self = try .spaceUpdate(SpaceUpdateParams(from: decoder))
        case .spaceDelete: self = try .spaceDelete(SpaceDeleteParams(from: decoder))
        // Tier 2D
        case .windowKeepOnTop: self = .windowKeepOnTop
        case .windowAllDesktops: self = .windowAllDesktops
        case .windowLockSize: self = .windowLockSize
        case .windowSetOpacity: self = try .windowSetOpacity(WindowSetOpacityParams(from: decoder))
        case .windowFullScreen: self = .windowFullScreen
        case .windowMinimize: self = .windowMinimize
        // Tier 2E
        case .siteSettingsGet: self = try .siteSettingsGet(SiteSettingsGetParams(from: decoder))
        case .siteSettingsSet: self = try .siteSettingsSet(SiteSettingsSetParams(from: decoder))
        // Tier 2F
        case .devInspector: self = try .devInspector(DevInspectorParams(from: decoder))
        case .devConsole: self = try .devConsole(OptionalTabIDParams(from: decoder))
        case .devResources: self = try .devResources(OptionalTabIDParams(from: decoder))
        case .devProfiling: self = try .devProfiling(OptionalTabIDParams(from: decoder))
        case .devElementSelection: self = try .devElementSelection(OptionalTabIDParams(from: decoder))
        case .devEmptyCaches: self = .devEmptyCaches
        case .devConsoleLog: self = try .devConsoleLog(DevConsoleLogParams(from: decoder))
        case .devNetworkLog: self = try .devNetworkLog(DevNetworkLogParams(from: decoder))
        case .devCookies: self = try .devCookies(DevCookiesParams(from: decoder))
        case .devStorage: self = try .devStorage(DevStorageParams(from: decoder))
        // Tier 3
        case .hover: self = try .hover(HoverParams(from: decoder))
        case .formInput: self = try .formInput(FormInputParams(from: decoder))
        // Global Settings
        case .settingsList: self = try .settingsList(SettingsListParams(from: decoder))
        case .settingsGet: self = try .settingsGet(SettingsGetParams(from: decoder))
        case .settingsSet: self = try .settingsSet(SettingsSetParams(from: decoder))
        // Compound Commands
        case .navigateAndRead: self = try .navigateAndRead(NavigateAndReadParams(from: decoder))
        case .clickAndRead: self = try .clickAndRead(ClickAndReadParams(from: decoder))
        case .fillForm: self = try .fillForm(FillFormParams(from: decoder))
        case .scrollAndRead: self = try .scrollAndRead(ScrollAndReadParams(from: decoder))
        case .findElements: self = try .findElements(FindElementsParams(from: decoder))
        // Program Execution
        case .execProgram: self = try .execProgram(ExecProgramParams(from: decoder))
        case .resumeProgram: self = try .resumeProgram(ResumeProgramParams(from: decoder))
        // Cookie Consent
        case .dismissCookies: self = try .dismissCookies(DismissCookiesParams(from: decoder))
        // Headless Fetch
        case .fetch: self = try .fetch(FetchParams(from: decoder))
        case .navigateNewTab: self = try .navigateNewTab(NavigateNewTabParams(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKey_.self)

        switch self {
        // Existing
        case .ping:
            try container.encode("ping", forKey: .type)
        case .health:
            try container.encode("health", forKey: .type)
        case .state:
            try container.encode("state", forKey: .type)
        case let .screenshot(params):
            try container.encode("screenshot", forKey: .type)
            try params.encode(to: encoder)
        case let .pageContent(params):
            try container.encode("pageContent", forKey: .type)
            try params.encode(to: encoder)
        case let .click(params):
            try container.encode("click", forKey: .type)
            try params.encode(to: encoder)
        case let .type(params):
            try container.encode("type", forKey: .type)
            try params.encode(to: encoder)
        case let .scroll(params):
            try container.encode("scroll", forKey: .type)
            try params.encode(to: encoder)
        case let .navigate(params):
            try container.encode("navigate", forKey: .type)
            try params.encode(to: encoder)
        case let .navigateAndWait(params):
            try container.encode("navigateAndWait", forKey: .type)
            try params.encode(to: encoder)
        case let .tabList(params):
            try container.encode("tabList", forKey: .type)
            try params.encode(to: encoder)
        case let .tabGet(params):
            try container.encode("tabGet", forKey: .type)
            try params.encode(to: encoder)
        case let .tabOpen(params):
            try container.encode("tabOpen", forKey: .type)
            try params.encode(to: encoder)
        case let .tabClose(params):
            try container.encode("tabClose", forKey: .type)
            try params.encode(to: encoder)
        case let .tabActivate(params):
            try container.encode("tabActivate", forKey: .type)
            try params.encode(to: encoder)
        case .spaceList:
            try container.encode("spaceList", forKey: .type)
        case let .spaceSwitch(params):
            try container.encode("spaceSwitch", forKey: .type)
            try params.encode(to: encoder)
        case let .windowResize(params):
            try container.encode("windowResize", forKey: .type)
            try params.encode(to: encoder)
        case let .windowMove(params):
            try container.encode("windowMove", forKey: .type)
            try params.encode(to: encoder)
        case .windowCenter:
            try container.encode("windowCenter", forKey: .type)
        case .windowInfo:
            try container.encode("windowInfo", forKey: .type)
        case .refPaneShow:
            try container.encode("refPaneShow", forKey: .type)
        case .refPaneHide:
            try container.encode("refPaneHide", forKey: .type)
        case .refPaneToggle:
            try container.encode("refPaneToggle", forKey: .type)
        case let .hotkey(params):
            try container.encode("hotkey", forKey: .type)
            try params.encode(to: encoder)
        case .sidebarToggle:
            try container.encode("sidebarToggle", forKey: .type)
        case .inspectorToggle:
            try container.encode("inspectorToggle", forKey: .type)
        case .commandLens:
            try container.encode("commandLens", forKey: .type)
        case .addressLens:
            try container.encode("addressLens", forKey: .type)
        // UI Accessibility Tree
        case let .uiAXTree(params):
            try container.encode("uiAXTree", forKey: .type)
            try params.encode(to: encoder)
        case let .uiAXClick(params):
            try container.encode("uiAXClick", forKey: .type)
            try params.encode(to: encoder)
        // Tier 1A
        case let .tabPin(params):
            try container.encode("tabPin", forKey: .type)
            try params.encode(to: encoder)
        case let .tabDuplicate(params):
            try container.encode("tabDuplicate", forKey: .type)
            try params.encode(to: encoder)
        case let .tabRename(params):
            try container.encode("tabRename", forKey: .type)
            try params.encode(to: encoder)
        case let .tabMute(params):
            try container.encode("tabMute", forKey: .type)
            try params.encode(to: encoder)
        case let .tabGoBack(params):
            try container.encode("tabGoBack", forKey: .type)
            try params.encode(to: encoder)
        case let .tabGoForward(params):
            try container.encode("tabGoForward", forKey: .type)
            try params.encode(to: encoder)
        case .tabNext:
            try container.encode("tabNext", forKey: .type)
        case .tabPrevious:
            try container.encode("tabPrevious", forKey: .type)
        case let .tabDetail(params):
            try container.encode("tabDetail", forKey: .type)
            try params.encode(to: encoder)
        case let .tabCloseOthers(params):
            try container.encode("tabCloseOthers", forKey: .type)
            try params.encode(to: encoder)
        case .tabReopenClosed:
            try container.encode("tabReopenClosed", forKey: .type)
        case .tabRecentlyClosed:
            try container.encode("tabRecentlyClosed", forKey: .type)
        case let .tabMoveToSpace(params):
            try container.encode("tabMoveToSpace", forKey: .type)
            try params.encode(to: encoder)
        case let .tabMoveToGroup(params):
            try container.encode("tabMoveToGroup", forKey: .type)
            try params.encode(to: encoder)
        case let .tabRemoveFromGroup(params):
            try container.encode("tabRemoveFromGroup", forKey: .type)
            try params.encode(to: encoder)
        case let .tabMoveToRefPane(params):
            try container.encode("tabMoveToRefPane", forKey: .type)
            try params.encode(to: encoder)
        case let .tabReorder(params):
            try container.encode("tabReorder", forKey: .type)
            try params.encode(to: encoder)
        case let .tabMarkRead(params):
            try container.encode("tabMarkRead", forKey: .type)
            try params.encode(to: encoder)
        case let .tabMarkUnread(params):
            try container.encode("tabMarkUnread", forKey: .type)
            try params.encode(to: encoder)
        case let .tabCopyURL(params):
            try container.encode("tabCopyURL", forKey: .type)
            try params.encode(to: encoder)
        case let .tabReload(params):
            try container.encode("tabReload", forKey: .type)
            try params.encode(to: encoder)
        case let .tabIsLoading(params):
            try container.encode("tabIsLoading", forKey: .type)
            try params.encode(to: encoder)
        case let .tabURL(params):
            try container.encode("tabURL", forKey: .type)
            try params.encode(to: encoder)
        case let .tabWaitLoaded(params):
            try container.encode("tabWaitLoaded", forKey: .type)
            try params.encode(to: encoder)
        // Tier 1B
        case let .groupList(params):
            try container.encode("groupList", forKey: .type)
            try params.encode(to: encoder)
        case let .groupCreate(params):
            try container.encode("groupCreate", forKey: .type)
            try params.encode(to: encoder)
        case let .groupDelete(params):
            try container.encode("groupDelete", forKey: .type)
            try params.encode(to: encoder)
        case let .groupRename(params):
            try container.encode("groupRename", forKey: .type)
            try params.encode(to: encoder)
        case let .groupSetColor(params):
            try container.encode("groupSetColor", forKey: .type)
            try params.encode(to: encoder)
        case let .groupSetIcon(params):
            try container.encode("groupSetIcon", forKey: .type)
            try params.encode(to: encoder)
        case let .groupToggleCollapsed(params):
            try container.encode("groupToggleCollapsed", forKey: .type)
            try params.encode(to: encoder)
        // Tier 1C
        case let .pageZoomIn(params):
            try container.encode("pageZoomIn", forKey: .type)
            try params.encode(to: encoder)
        case let .pageZoomOut(params):
            try container.encode("pageZoomOut", forKey: .type)
            try params.encode(to: encoder)
        case let .pageZoomReset(params):
            try container.encode("pageZoomReset", forKey: .type)
            try params.encode(to: encoder)
        case let .pageFind(params):
            try container.encode("pageFind", forKey: .type)
            try params.encode(to: encoder)
        case let .pageFindNext(params):
            try container.encode("pageFindNext", forKey: .type)
            try params.encode(to: encoder)
        case let .pageFindPrevious(params):
            try container.encode("pageFindPrevious", forKey: .type)
            try params.encode(to: encoder)
        case let .pageFindDismiss(params):
            try container.encode("pageFindDismiss", forKey: .type)
            try params.encode(to: encoder)
        case let .pageExecJS(params):
            try container.encode("pageExecJS", forKey: .type)
            try params.encode(to: encoder)
        case let .pageSource(params):
            try container.encode("pageSource", forKey: .type)
            try params.encode(to: encoder)
        case let .pageVideoViewer(params):
            try container.encode("pageVideoViewer", forKey: .type)
            try params.encode(to: encoder)
        case let .pagePiP(params):
            try container.encode("pagePiP", forKey: .type)
            try params.encode(to: encoder)
        // Tier 1D
        case let .refPaneAddTab(params):
            try container.encode("refPaneAddTab", forKey: .type)
            try params.encode(to: encoder)
        case let .refPaneCloseTab(params):
            try container.encode("refPaneCloseTab", forKey: .type)
            try params.encode(to: encoder)
        case .refPaneListTabs:
            try container.encode("refPaneListTabs", forKey: .type)
        case let .refPaneActivateTab(params):
            try container.encode("refPaneActivateTab", forKey: .type)
            try params.encode(to: encoder)
        case let .refPaneMoveToMain(params):
            try container.encode("refPaneMoveToMain", forKey: .type)
            try params.encode(to: encoder)
        // Tier 1E
        case let .visualHighlight(params):
            try container.encode("visualHighlight", forKey: .type)
            try params.encode(to: encoder)
        case let .visualCursor(params):
            try container.encode("visualCursor", forKey: .type)
            try params.encode(to: encoder)
        case let .visualClick(params):
            try container.encode("visualClick", forKey: .type)
            try params.encode(to: encoder)
        case let .visualScrollTo(params):
            try container.encode("visualScrollTo", forKey: .type)
            try params.encode(to: encoder)
        case .visualClear:
            try container.encode("visualClear", forKey: .type)
        // Tier 2A
        case let .bookmarkList(params):
            try container.encode("bookmarkList", forKey: .type)
            try params.encode(to: encoder)
        case let .bookmarkCreate(params):
            try container.encode("bookmarkCreate", forKey: .type)
            try params.encode(to: encoder)
        case let .bookmarkDelete(params):
            try container.encode("bookmarkDelete", forKey: .type)
            try params.encode(to: encoder)
        case let .bookmarkFavorite(params):
            try container.encode("bookmarkFavorite", forKey: .type)
            try params.encode(to: encoder)
        case let .bookmarkUnfavorite(params):
            try container.encode("bookmarkUnfavorite", forKey: .type)
            try params.encode(to: encoder)
        case .bookmarkFolderList:
            try container.encode("bookmarkFolderList", forKey: .type)
        case let .bookmarkFolderCreate(params):
            try container.encode("bookmarkFolderCreate", forKey: .type)
            try params.encode(to: encoder)
        // Tier 2B
        case let .historyList(params):
            try container.encode("historyList", forKey: .type)
            try params.encode(to: encoder)
        case let .historySearch(params):
            try container.encode("historySearch", forKey: .type)
            try params.encode(to: encoder)
        case let .historyClear(params):
            try container.encode("historyClear", forKey: .type)
            try params.encode(to: encoder)
        case let .historyFrequent(params):
            try container.encode("historyFrequent", forKey: .type)
            try params.encode(to: encoder)
        // Tier 2C
        case let .spaceCreate(params):
            try container.encode("spaceCreate", forKey: .type)
            try params.encode(to: encoder)
        case let .spaceUpdate(params):
            try container.encode("spaceUpdate", forKey: .type)
            try params.encode(to: encoder)
        case let .spaceDelete(params):
            try container.encode("spaceDelete", forKey: .type)
            try params.encode(to: encoder)
        // Tier 2D
        case .windowKeepOnTop:
            try container.encode("windowKeepOnTop", forKey: .type)
        case .windowAllDesktops:
            try container.encode("windowAllDesktops", forKey: .type)
        case .windowLockSize:
            try container.encode("windowLockSize", forKey: .type)
        case let .windowSetOpacity(params):
            try container.encode("windowSetOpacity", forKey: .type)
            try params.encode(to: encoder)
        case .windowFullScreen:
            try container.encode("windowFullScreen", forKey: .type)
        case .windowMinimize:
            try container.encode("windowMinimize", forKey: .type)
        // Tier 2E
        case let .siteSettingsGet(params):
            try container.encode("siteSettingsGet", forKey: .type)
            try params.encode(to: encoder)
        case let .siteSettingsSet(params):
            try container.encode("siteSettingsSet", forKey: .type)
            try params.encode(to: encoder)
        // Tier 2F
        case let .devInspector(params):
            try container.encode("devInspector", forKey: .type)
            try params.encode(to: encoder)
        case let .devConsole(params):
            try container.encode("devConsole", forKey: .type)
            try params.encode(to: encoder)
        case let .devResources(params):
            try container.encode("devResources", forKey: .type)
            try params.encode(to: encoder)
        case let .devProfiling(params):
            try container.encode("devProfiling", forKey: .type)
            try params.encode(to: encoder)
        case let .devElementSelection(params):
            try container.encode("devElementSelection", forKey: .type)
            try params.encode(to: encoder)
        case .devEmptyCaches:
            try container.encode("devEmptyCaches", forKey: .type)
        case let .devConsoleLog(params):
            try container.encode("devConsoleLog", forKey: .type)
            try params.encode(to: encoder)
        case let .devNetworkLog(params):
            try container.encode("devNetworkLog", forKey: .type)
            try params.encode(to: encoder)
        case let .devCookies(params):
            try container.encode("devCookies", forKey: .type)
            try params.encode(to: encoder)
        case let .devStorage(params):
            try container.encode("devStorage", forKey: .type)
            try params.encode(to: encoder)
        // Tier 3
        case let .hover(params):
            try container.encode("hover", forKey: .type)
            try params.encode(to: encoder)
        case let .formInput(params):
            try container.encode("formInput", forKey: .type)
            try params.encode(to: encoder)
        // Global Settings
        case let .settingsList(params):
            try container.encode("settingsList", forKey: .type)
            try params.encode(to: encoder)
        case let .settingsGet(params):
            try container.encode("settingsGet", forKey: .type)
            try params.encode(to: encoder)
        case let .settingsSet(params):
            try container.encode("settingsSet", forKey: .type)
            try params.encode(to: encoder)
        // Compound Commands
        case let .navigateAndRead(params):
            try container.encode("navigateAndRead", forKey: .type)
            try params.encode(to: encoder)
        case let .clickAndRead(params):
            try container.encode("clickAndRead", forKey: .type)
            try params.encode(to: encoder)
        case let .fillForm(params):
            try container.encode("fillForm", forKey: .type)
            try params.encode(to: encoder)
        case let .scrollAndRead(params):
            try container.encode("scrollAndRead", forKey: .type)
            try params.encode(to: encoder)
        case let .findElements(params):
            try container.encode("findElements", forKey: .type)
            try params.encode(to: encoder)
        // Program Execution
        case let .execProgram(params):
            try container.encode("exec_program", forKey: .type)
            try params.encode(to: encoder)
        case let .resumeProgram(params):
            try container.encode("resume_program", forKey: .type)
            try params.encode(to: encoder)
        // Cookie Consent
        case let .dismissCookies(params):
            try container.encode("dismiss_cookies", forKey: .type)
            try params.encode(to: encoder)
        // Headless Fetch
        case let .fetch(params):
            try container.encode("fetch", forKey: .type)
            try params.encode(to: encoder)
        case let .navigateNewTab(params):
            try container.encode("navigateNewTab", forKey: .type)
            try params.encode(to: encoder)
        }
    }

    private enum CodingKey_: String, CodingKey {
        case type
    }
}

// MARK: - Response

/// A response from the Refrax control server to the CLI.
///
/// Uses a flat JSON format with a `type` discriminator:
/// ```json
/// {"type": "ok", "message": "pong"}
/// {"type": "tabs", "tabs": [...]}
/// {"type": "error", "code": "not_found", "message": "Tab not found"}
/// ```
public enum ControlResponse: Sendable {
    case ok(String? = nil)
    case state(CTL.BrowserStateInfo)
    case screenshot(CTL.ScreenshotInfo)
    case pageContent(String)
    case tabs([CTL.TabInfo])
    case tab(CTL.TabInfo)
    case spaces([CTL.SpaceInfo])
    case windowInfo(CTL.WindowInfoData)
    case actionResult(CTL.ActionResultInfo)
    case error(CTL.ErrorInfo)

    // New response types
    case tabDetail(CTL.TabDetailInfo)
    case groups([CTL.GroupInfo])
    case group(CTL.GroupInfo)
    case javascript(String)
    case bookmarks([CTL.BookmarkInfo])
    case bookmarkFolders([CTL.BookmarkFolderInfo])
    case historyEntries([CTL.HistoryEntryInfo])
    case siteSettings(CTL.SiteSettingsInfo)
    case consoleMessages([CTL.ConsoleMessage])
    case networkEntries([CTL.NetworkEntry])
    case cookies([CTL.CookieInfo])
    case storageEntries([CTL.StorageEntry])
    case recentlyClosedTabs([CTL.RecentlyClosedTabInfo])
    case refPaneTabs([CTL.RefPaneTabInfo])
    case settingsEntries([CTL.SettingEntryInfo])
    case health(CTL.HealthInfo)
    case foundElements([CTL.FoundElementInfo])
    case execResult(CTL.ExecResultInfo)
    case ping(CTL.PingInfo)
    case humanRequested(CTL.HumanRequestInfo)
}

// MARK: - Response Data Types

/// Namespace for control protocol data types to avoid collisions with API types.
public enum CTL {
    public struct TabInfo: Codable, Sendable {
        public let id: String
        public let title: String
        public let url: String?
        public let isActive: Bool
        public let spaceID: String?
        public let isLoading: Bool
        public let isPinned: Bool
        public let isUnread: Bool?
        public let customName: String?
        public let groupID: String?
        public let pageCount: Int

        public init(id: String, title: String, url: String?, isActive: Bool, spaceID: String?, isLoading: Bool, isPinned: Bool, isUnread: Bool?, customName: String?, groupID: String?, pageCount: Int) {
            self.id = id
            self.title = title
            self.url = url
            self.isActive = isActive
            self.spaceID = spaceID
            self.isLoading = isLoading
            self.isPinned = isPinned
            self.isUnread = isUnread
            self.customName = customName
            self.groupID = groupID
            self.pageCount = pageCount
        }
    }

    public struct SpaceInfo: Codable, Sendable {
        public let id: String
        public let name: String
        public let tabCount: Int
        public let isActive: Bool

        public init(id: String, name: String, tabCount: Int, isActive: Bool) {
            self.id = id
            self.name = name
            self.tabCount = tabCount
            self.isActive = isActive
        }
    }

    public struct BrowserStateInfo: Codable, Sendable {
        public let tabs: [TabInfo]
        public let spaces: [SpaceInfo]
        public let activeTabID: String?
        public let activeSpaceID: String?

        public init(tabs: [TabInfo], spaces: [SpaceInfo], activeTabID: String?, activeSpaceID: String?) {
            self.tabs = tabs
            self.spaces = spaces
            self.activeTabID = activeTabID
            self.activeSpaceID = activeSpaceID
        }
    }

    public struct ScreenshotInfo: Codable, Sendable {
        public let data: String
        public let width: Int
        public let height: Int
        public let pixelWidth: Int?
        public let pixelHeight: Int?
        public let scaleFactor: Double?

        public init(
            data: String,
            width: Int,
            height: Int,
            pixelWidth: Int? = nil,
            pixelHeight: Int? = nil,
            scaleFactor: Double? = nil,
        ) {
            self.data = data
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.scaleFactor = scaleFactor
        }
    }

    public struct WindowInfoData: Codable, Sendable {
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int
        public let isSidebarCollapsed: Bool
        public let isInspectorCollapsed: Bool
        public let isReferencePaneVisible: Bool

        public init(x: Int, y: Int, width: Int, height: Int, isSidebarCollapsed: Bool, isInspectorCollapsed: Bool, isReferencePaneVisible: Bool) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.isSidebarCollapsed = isSidebarCollapsed
            self.isInspectorCollapsed = isInspectorCollapsed
            self.isReferencePaneVisible = isReferencePaneVisible
        }
    }

    public struct ActionResultInfo: Codable, Sendable {
        public let success: Bool
        public let message: String?

        public init(success: Bool, message: String?) {
            self.success = success
            self.message = message
        }
    }

    public struct ErrorInfo: Codable, Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    // New data types

    public struct TabDetailInfo: Codable, Sendable {
        public let id: String
        public let title: String
        public let url: String?
        public let isActive: Bool
        public let isLoading: Bool
        public let isPinned: Bool
        public let isUnread: Bool
        public let customName: String?
        public let groupID: String?
        public let groupName: String?
        public let spaceID: String?
        public let isReferenceTab: Bool
        public let canGoBack: Bool
        public let canGoForward: Bool
        public let isMuted: Bool
        public let pageCount: Int
        public let pages: [PageInfo]

        public init(id: String, title: String, url: String?, isActive: Bool, isLoading: Bool, isPinned: Bool, isUnread: Bool, customName: String?, groupID: String?, groupName: String?, spaceID: String?, isReferenceTab: Bool, canGoBack: Bool, canGoForward: Bool, isMuted: Bool, pageCount: Int, pages: [PageInfo]) {
            self.id = id
            self.title = title
            self.url = url
            self.isActive = isActive
            self.isLoading = isLoading
            self.isPinned = isPinned
            self.isUnread = isUnread
            self.customName = customName
            self.groupID = groupID
            self.groupName = groupName
            self.spaceID = spaceID
            self.isReferenceTab = isReferenceTab
            self.canGoBack = canGoBack
            self.canGoForward = canGoForward
            self.isMuted = isMuted
            self.pageCount = pageCount
            self.pages = pages
        }
    }

    public struct PageInfo: Codable, Sendable {
        public let id: String
        public let url: String
        public let title: String
        public let position: String
        public let isActive: Bool

        public init(id: String, url: String, title: String, position: String, isActive: Bool) {
            self.id = id
            self.url = url
            self.title = title
            self.position = position
            self.isActive = isActive
        }
    }

    public struct GroupInfo: Codable, Sendable {
        public let id: String
        public let name: String
        public let color: String
        public let iconName: String?
        public let spaceID: String?
        public let tabCount: Int
        public let isCollapsed: Bool

        public init(id: String, name: String, color: String, iconName: String?, spaceID: String?, tabCount: Int, isCollapsed: Bool) {
            self.id = id
            self.name = name
            self.color = color
            self.iconName = iconName
            self.spaceID = spaceID
            self.tabCount = tabCount
            self.isCollapsed = isCollapsed
        }
    }

    public struct BookmarkInfo: Codable, Sendable {
        public let id: String
        public let title: String
        public let url: String
        public let folderID: String?
        public let isFavorite: Bool
        public let dateAdded: String?

        public init(id: String, title: String, url: String, folderID: String?, isFavorite: Bool, dateAdded: String?) {
            self.id = id
            self.title = title
            self.url = url
            self.folderID = folderID
            self.isFavorite = isFavorite
            self.dateAdded = dateAdded
        }
    }

    public struct BookmarkFolderInfo: Codable, Sendable {
        public let id: String
        public let name: String
        public let parentID: String?
        public let bookmarkCount: Int

        public init(id: String, name: String, parentID: String?, bookmarkCount: Int) {
            self.id = id
            self.name = name
            self.parentID = parentID
            self.bookmarkCount = bookmarkCount
        }
    }

    public struct HistoryEntryInfo: Codable, Sendable {
        public let id: String
        public let title: String
        public let url: String
        public let lastVisited: String
        public let visitCount: Int

        public init(id: String, title: String, url: String, lastVisited: String, visitCount: Int) {
            self.id = id
            self.title = title
            self.url = url
            self.lastVisited = lastVisited
            self.visitCount = visitCount
        }
    }

    public struct SiteSettingsInfo: Codable, Sendable {
        public let domain: String
        public let zoom: Int?
        public let javascript: Bool?
        public let contentBlockers: Bool?

        public init(domain: String, zoom: Int?, javascript: Bool?, contentBlockers: Bool?) {
            self.domain = domain
            self.zoom = zoom
            self.javascript = javascript
            self.contentBlockers = contentBlockers
        }
    }

    public struct ConsoleMessage: Codable, Sendable {
        public let level: String
        public let message: String
        public let timestamp: Double

        public init(level: String, message: String, timestamp: Double) {
            self.level = level
            self.message = message
            self.timestamp = timestamp
        }
    }

    public struct NetworkEntry: Codable, Sendable {
        public let url: String
        public let method: String
        public let status: Int?
        public let contentType: String?
        public let duration: Double?
        public let timestamp: Double

        public init(url: String, method: String, status: Int?, contentType: String?, duration: Double?, timestamp: Double) {
            self.url = url
            self.method = method
            self.status = status
            self.contentType = contentType
            self.duration = duration
            self.timestamp = timestamp
        }
    }

    public struct CookieInfo: Codable, Sendable {
        public let name: String
        public let value: String
        public let domain: String
        public let path: String
        public let isSecure: Bool
        public let isHTTPOnly: Bool
        public let expiresDate: String?

        public init(name: String, value: String, domain: String, path: String, isSecure: Bool, isHTTPOnly: Bool, expiresDate: String?) {
            self.name = name
            self.value = value
            self.domain = domain
            self.path = path
            self.isSecure = isSecure
            self.isHTTPOnly = isHTTPOnly
            self.expiresDate = expiresDate
        }
    }

    public struct StorageEntry: Codable, Sendable {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public struct RecentlyClosedTabInfo: Codable, Sendable {
        public let title: String
        public let url: String
        public let closedAt: String

        public init(title: String, url: String, closedAt: String) {
            self.title = title
            self.url = url
            self.closedAt = closedAt
        }
    }

    public struct RefPaneTabInfo: Codable, Sendable {
        public let id: String
        public let title: String
        public let url: String?
        public let isActive: Bool

        public init(id: String, title: String, url: String?, isActive: Bool) {
            self.id = id
            self.title = title
            self.url = url
            self.isActive = isActive
        }
    }

    public struct SettingEntryInfo: Codable, Sendable {
        public let key: String
        public let displayName: String
        public let value: String
        public let category: String

        public init(key: String, displayName: String, value: String, category: String) {
            self.key = key
            self.displayName = displayName
            self.value = value
            self.category = category
        }
    }

    public struct HealthInfo: Codable, Sendable {
        public let appVersion: String
        public let protocolVersion: Int
        public let tabCount: Int
        public let windowCount: Int
        public let spaceCount: Int
        public let memoryUsageMB: Int
        public let uptimeSeconds: Int

        public init(
            appVersion: String,
            protocolVersion: Int,
            tabCount: Int,
            windowCount: Int,
            spaceCount: Int,
            memoryUsageMB: Int,
            uptimeSeconds: Int,
        ) {
            self.appVersion = appVersion
            self.protocolVersion = protocolVersion
            self.tabCount = tabCount
            self.windowCount = windowCount
            self.spaceCount = spaceCount
            self.memoryUsageMB = memoryUsageMB
            self.uptimeSeconds = uptimeSeconds
        }
    }

    public struct FoundElementInfo: Codable, Sendable {
        public let ref: String
        public let text: String
        public let tag: String
        public let role: String?
        public let href: String?
        public let inputType: String?
        public let rect: CGRect?

        public init(ref: String, text: String, tag: String, role: String? = nil, href: String? = nil, inputType: String? = nil, rect: CGRect? = nil) {
            self.ref = ref
            self.text = text
            self.tag = tag
            self.role = role
            self.href = href
            self.inputType = inputType
            self.rect = rect
        }
    }

    public struct ExecResultInfo: Codable, Sendable {
        public let output: [String]
        public let success: Bool
        public let error: String?
        public let stepsExecuted: Int
        public let stepsTotal: Int

        public init(output: [String], success: Bool, error: String? = nil, stepsExecuted: Int, stepsTotal: Int) {
            self.output = output
            self.success = success
            self.error = error
            self.stepsExecuted = stepsExecuted
            self.stepsTotal = stepsTotal
        }
    }

    public struct PingInfo: Codable, Sendable {
        public let protocolVersion: Int
        public let appVersion: String

        public init(protocolVersion: Int, appVersion: String) {
            self.protocolVersion = protocolVersion
            self.appVersion = appVersion
        }
    }

    public struct HumanRequestInfo: Codable, Sendable {
        public let token: String
        public let description: String

        public init(token: String, description: String) {
            self.token = token
            self.description = description
        }
    }
}

// MARK: - Response Codable

extension ControlResponse: Codable {
    private enum TypeKey: String, Codable {
        case ok
        case state
        case screenshot
        case pageContent
        case tabs
        case tab
        case spaces
        case windowInfo
        case actionResult
        case error
        case tabDetail
        case groups
        case group
        case javascript
        case bookmarks
        case bookmarkFolders
        case historyEntries
        case siteSettings
        case consoleMessages
        case networkEntries
        case cookies
        case storageEntries
        case recentlyClosedTabs
        case refPaneTabs
        case settingsEntries
        case health
        case foundElements
        case execResult = "exec_result"
        case ping
        case humanRequested = "human_requested"
    }

    private struct TypeContainer: Decodable {
        let type: TypeKey
    }

    public init(from decoder: any Decoder) throws {
        let typeContainer = try TypeContainer(from: decoder)
        let c = try decoder.container(keyedBy: PayloadKey.self)

        switch typeContainer.type {
        case .ok:
            self = try .ok(c.decodeIfPresent(String.self, forKey: .message))
        case .state:
            self = try .state(c.decode(CTL.BrowserStateInfo.self, forKey: .state))
        case .screenshot:
            self = try .screenshot(CTL.ScreenshotInfo(from: decoder))
        case .pageContent:
            self = try .pageContent(c.decode(String.self, forKey: .content))
        case .tabs:
            self = try .tabs(c.decode([CTL.TabInfo].self, forKey: .tabs))
        case .tab:
            self = try .tab(c.decode(CTL.TabInfo.self, forKey: .tab))
        case .spaces:
            self = try .spaces(c.decode([CTL.SpaceInfo].self, forKey: .spaces))
        case .windowInfo:
            self = try .windowInfo(CTL.WindowInfoData(from: decoder))
        case .actionResult:
            self = try .actionResult(CTL.ActionResultInfo(from: decoder))
        case .error:
            self = try .error(CTL.ErrorInfo(from: decoder))
        case .tabDetail:
            self = try .tabDetail(c.decode(CTL.TabDetailInfo.self, forKey: .data))
        case .groups:
            self = try .groups(c.decode([CTL.GroupInfo].self, forKey: .data))
        case .group:
            self = try .group(c.decode(CTL.GroupInfo.self, forKey: .data))
        case .javascript:
            self = try .javascript(c.decode(String.self, forKey: .data))
        case .bookmarks:
            self = try .bookmarks(c.decode([CTL.BookmarkInfo].self, forKey: .data))
        case .bookmarkFolders:
            self = try .bookmarkFolders(c.decode([CTL.BookmarkFolderInfo].self, forKey: .data))
        case .historyEntries:
            self = try .historyEntries(c.decode([CTL.HistoryEntryInfo].self, forKey: .data))
        case .siteSettings:
            self = try .siteSettings(c.decode(CTL.SiteSettingsInfo.self, forKey: .data))
        case .consoleMessages:
            self = try .consoleMessages(c.decode([CTL.ConsoleMessage].self, forKey: .data))
        case .networkEntries:
            self = try .networkEntries(c.decode([CTL.NetworkEntry].self, forKey: .data))
        case .cookies:
            self = try .cookies(c.decode([CTL.CookieInfo].self, forKey: .data))
        case .storageEntries:
            self = try .storageEntries(c.decode([CTL.StorageEntry].self, forKey: .data))
        case .recentlyClosedTabs:
            self = try .recentlyClosedTabs(c.decode([CTL.RecentlyClosedTabInfo].self, forKey: .data))
        case .refPaneTabs:
            self = try .refPaneTabs(c.decode([CTL.RefPaneTabInfo].self, forKey: .data))
        case .settingsEntries:
            self = try .settingsEntries(c.decode([CTL.SettingEntryInfo].self, forKey: .data))
        case .health:
            self = try .health(c.decode(CTL.HealthInfo.self, forKey: .data))
        case .foundElements:
            self = try .foundElements(c.decode([CTL.FoundElementInfo].self, forKey: .data))
        case .execResult:
            self = try .execResult(c.decode(CTL.ExecResultInfo.self, forKey: .data))
        case .ping:
            self = try .ping(c.decode(CTL.PingInfo.self, forKey: .data))
        case .humanRequested:
            self = try .humanRequested(c.decode(CTL.HumanRequestInfo.self, forKey: .data))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PayloadKey.self)

        switch self {
        case let .ok(message):
            try container.encode("ok", forKey: .type)
            try container.encodeIfPresent(message, forKey: .message)
        case let .state(info):
            try container.encode("state", forKey: .type)
            try container.encode(info, forKey: .state)
        case let .screenshot(info):
            try container.encode("screenshot", forKey: .type)
            try info.encode(to: encoder)
        case let .pageContent(content):
            try container.encode("pageContent", forKey: .type)
            try container.encode(content, forKey: .content)
        case let .tabs(tabs):
            try container.encode("tabs", forKey: .type)
            try container.encode(tabs, forKey: .tabs)
        case let .tab(tab):
            try container.encode("tab", forKey: .type)
            try container.encode(tab, forKey: .tab)
        case let .spaces(spaces):
            try container.encode("spaces", forKey: .type)
            try container.encode(spaces, forKey: .spaces)
        case let .windowInfo(info):
            try container.encode("windowInfo", forKey: .type)
            try info.encode(to: encoder)
        case let .actionResult(info):
            try container.encode("actionResult", forKey: .type)
            try info.encode(to: encoder)
        case let .error(info):
            try container.encode("error", forKey: .type)
            try info.encode(to: encoder)
        case let .tabDetail(info):
            try container.encode("tabDetail", forKey: .type)
            try container.encode(info, forKey: .data)
        case let .groups(list):
            try container.encode("groups", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .group(info):
            try container.encode("group", forKey: .type)
            try container.encode(info, forKey: .data)
        case let .javascript(result):
            try container.encode("javascript", forKey: .type)
            try container.encode(result, forKey: .data)
        case let .bookmarks(list):
            try container.encode("bookmarks", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .bookmarkFolders(list):
            try container.encode("bookmarkFolders", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .historyEntries(list):
            try container.encode("historyEntries", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .siteSettings(info):
            try container.encode("siteSettings", forKey: .type)
            try container.encode(info, forKey: .data)
        case let .consoleMessages(list):
            try container.encode("consoleMessages", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .networkEntries(list):
            try container.encode("networkEntries", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .cookies(list):
            try container.encode("cookies", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .storageEntries(list):
            try container.encode("storageEntries", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .recentlyClosedTabs(list):
            try container.encode("recentlyClosedTabs", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .refPaneTabs(list):
            try container.encode("refPaneTabs", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .settingsEntries(list):
            try container.encode("settingsEntries", forKey: .type)
            try container.encode(list, forKey: .data)
        case let .health(info):
            try container.encode("health", forKey: .type)
            try container.encode(info, forKey: .data)
        case let .foundElements(elements):
            try container.encode("foundElements", forKey: .type)
            try container.encode(elements, forKey: .data)
        case let .execResult(info):
            try container.encode("exec_result", forKey: .type)
            try container.encode(info, forKey: .data)
        case let .ping(info):
            try container.encode("ping", forKey: .type)
            try container.encode(info, forKey: .data)
        case let .humanRequested(info):
            try container.encode("human_requested", forKey: .type)
            try container.encode(info, forKey: .data)
        }
    }

    private enum PayloadKey: String, CodingKey {
        case type
        case message
        case state
        case content
        case tabs
        case tab
        case spaces
        case data
    }
}
