import Foundation
import RefraxProtocol

/// Prints a `ControlResponse` in human-readable or JSON format.
///
/// Respects `CLIConfig.quiet` (suppress success output) and
/// `CLIConfig.verbose` (print raw JSON request/response).
func handleResponse(_ response: ControlResponse, json: Bool = false) {
    // Verbose: always print the raw JSON response
    if CLIConfig.verbose {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(response),
           let str = String(data: data, encoding: .utf8) {
            printInfo("[response] \(str)")
        }
    }

    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        switch response {
        case let .error(info):
            printError("Error [\(info.code)]: \(info.message)")
            _Exit(1)
        default:
            if let data = try? encoder.encode(response),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        }
        return
    }

    // Quiet mode: suppress success messages, still show errors
    if CLIConfig.quiet {
        if case let .error(info) = response {
            printError("Error [\(info.code)]: \(info.message)")
            _Exit(1)
        }
        if case let .actionResult(info) = response, !info.success {
            printError(info.message ?? "Action failed")
            _Exit(1)
        }
        return
    }

    switch response {
    case let .ok(msg):
        print(msg ?? "OK")
    case let .error(info):
        printError("Error [\(info.code)]: \(info.message)")
        _Exit(1)
    case let .state(info):
        printBrowserState(info)
    case let .screenshot(info):
        print("Screenshot: \(info.width)x\(info.height)")
    case let .pageContent(content):
        print(content)
    case let .tabs(tabs):
        printTabs(tabs)
    case let .tab(tab):
        printTab(tab)
    case let .spaces(spaces):
        printSpaces(spaces)
    case let .windowInfo(info):
        printWindowInfo(info)
    case let .actionResult(info):
        if info.success {
            print(info.message ?? "OK")
        } else {
            printError(info.message ?? "Action failed")
            _Exit(1)
        }
    // New response types
    case let .tabDetail(info):
        printTabDetail(info)
    case let .groups(groups):
        printGroups(groups)
    case let .group(group):
        printGroup(group)
    case let .javascript(result):
        print(result)
    case let .bookmarks(bookmarks):
        printBookmarks(bookmarks)
    case let .bookmarkFolders(folders):
        printBookmarkFolders(folders)
    case let .historyEntries(entries):
        printHistoryEntries(entries)
    case let .siteSettings(settings):
        printSiteSettings(settings)
    case let .consoleMessages(messages):
        printConsoleMessages(messages)
    case let .networkEntries(entries):
        printNetworkEntries(entries)
    case let .cookies(cookies):
        printCookies(cookies)
    case let .storageEntries(entries):
        printStorageEntries(entries)
    case let .recentlyClosedTabs(tabs):
        printRecentlyClosedTabs(tabs)
    case let .settingsEntries(entries):
        printSettingsEntries(entries)
    case let .health(info):
        printHealth(info)
    case let .foundElements(elements):
        printFoundElements(elements)
    case let .execResult(info):
        printExecResult(info)
    case let .ping(info):
        print("pong (protocol: v\(info.protocolVersion), app: \(info.appVersion))")
    case let .humanRequested(info):
        printHumanRequest(info)
    case let .canvas(info):
        printCanvas(info)
    case let .islands(info):
        printIslands(info)
    case let .requestLog(info):
        printRequestLog(info)
    case let .requestExplanation(info):
        printRequestExplanation(info)
    }
}

func printRequestLog(_ info: CTL.RequestLogInfo) {
    if info.entries.isEmpty {
        print("No requests logged (\(info.engine))")
        return
    }
    for entry in info.entries {
        let decision = entry.decision.uppercased().padding(toLength: 10, withPad: " ", startingAt: 0)
        print("\(entry.seq) \(decision) \(entry.type.padding(toLength: 14, withPad: " ", startingAt: 0)) \(entry.url)")
        if let rule = entry.rule {
            let location = [entry.list, entry.line.map { "line \($0 + 1)" }].compactMap(\.self).joined(separator: ", ")
            print("    rule: \(rule)\(location.isEmpty ? "" : "  (\(location))")")
        }
        if let exception = entry.exceptionRule {
            print("    exception: \(exception)")
        }
    }
    let attributed = info.entries.contains { $0.exactness == "attributed" }
    print("\(info.entries.count) entries · \(info.engine) · next --since \(info.nextSequence)\(attributed ? " · rules attributed by Refrax" : "")")
}

func printRequestExplanation(_ info: CTL.RequestExplanationInfo) {
    let verdict = info.shouldBlock ? (info.redirected ? "REDIRECTED" : "BLOCKED") : (info.rewrittenURL != nil ? "REWRITTEN" : "ALLOWED")
    print("\(verdict)  \(info.url)")
    print("  from \(info.source) as \(info.type)")
    if info.siteAllowlisted {
        print("  Shields is off for this site: nothing is filtered here")
    }
    if let rule = info.rule {
        let location = [info.list, info.line.map { "line \($0 + 1)" }].compactMap(\.self).joined(separator: ", ")
        print("  rule: \(rule)\(location.isEmpty ? "" : "  (\(location))")\(info.important ? "  [important]" : "")")
    }
    if let exception = info.exceptionRule {
        let location = [info.exceptionList, info.exceptionLine.map { "line \($0 + 1)" }].compactMap(\.self).joined(separator: ", ")
        print("  exception: \(exception)\(location.isEmpty ? "" : "  (\(location))")")
    }
    if let rewritten = info.rewrittenURL {
        print("  loads: \(rewritten)")
    }
    if let csp = info.csp {
        print("  adds Content-Security-Policy: \(csp)")
    }
    if info.rule == nil, info.exceptionRule == nil {
        print("  no filter matches")
    }
}

func printIslands(_ info: CTL.IslandsInfo) {
    let reveal = info.isHeld ? "held" : info.isRevealed ? "up" : "down"
    print("Islands: \(reveal) · \(info.islands.count) islands · \(info.cards.count) cards")
    for island in info.islands {
        let marks = [island.isPinned ? "pinned" : nil, island.isVisible ? nil : "hidden"].compactMap(\.self).joined(separator: " · ")
        print("  \(island.title) [\(island.id.prefix(8))]  \(Int(island.x)),\(Int(island.y)) \(Int(island.width))×\(Int(island.height))\(marks.isEmpty ? "" : "  " + marks)")
        for (index, row) in island.rows.enumerated() {
            let panes = row.pageCount > 1 ? " · \(row.pageCount) panes" : ""
            print("    \(index)\(row.isCurrent ? " ▸" : "  ") \(row.title)\(panes)  [\(row.tabID.prefix(8))]")
        }
    }
    for card in info.cards {
        print("  card \(Int(card.x)),\(Int(card.y)) \(Int(card.width))×\(Int(card.height))  \(card.title)  [\(card.tabID.prefix(8))]")
    }
    if let panes = info.panes, panes.panes.count > 1 || panes.isEditing {
        let splits = String(format: "columns %.2f · rows %.2f", panes.columnSplit, panes.rowSplit)
        print("Panes: \(panes.panes.count)\(panes.isEditing ? " · editing" : "") · \(splits)")
        for (index, pane) in panes.panes.enumerated() {
            let cells = pane.cells.joined(separator: "+")
            print("  \(index)\(pane.isActive ? " ▸" : "  ") \(cells)  \(Int(pane.x)),\(Int(pane.y)) \(Int(pane.width))×\(Int(pane.height))  \(pane.title)  [\(pane.pageID.prefix(8))]")
        }
        if !panes.emptyCells.isEmpty {
            print("  empty: \(panes.emptyCells.joined(separator: ", "))")
        }
    }
}

/// Sends a `ControlRequest` via `ControlClient`, handles errors, and prints the response.
func sendAndHandle(_ request: ControlRequest, json: Bool = false) throws {
    if CLIConfig.verbose {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(request),
           let str = String(data: data, encoding: .utf8) {
            printInfo("[request] \(str)")
        }
    }
    let response = try ControlClient.send(request)
    handleResponse(response, json: json)
}

// MARK: - Existing Formatters

func printBrowserState(_ state: CTL.BrowserStateInfo) {
    for space in state.spaces {
        let activeMarker = space.isActive ? " [active]" : ""
        print("Space: \(space.name) (\(space.tabCount) tabs)\(activeMarker)")

        let spaceTabs = state.tabs.filter { $0.spaceID == space.id }
        for tab in spaceTabs {
            let prefix = tab.isActive ? "  * " : "    "
            let title = tab.title.isEmpty ? "(untitled)" : tab.title
            let url = tab.url ?? ""
            var flags: [String] = []
            if tab.isActive {
                flags.append("active")
            }
            if tab.isLoading {
                flags.append("loading")
            }
            if tab.isFavorite {
                flags.append("favorite")
            }
            if tab.pageCount > 1 {
                flags.append("\(tab.pageCount) pages")
            }
            let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"
            print("\(prefix)\(title) - \(url)\(flagStr)")
        }
    }

    // Favorites belong to no space
    let orphanTabs = state.tabs.filter { tab in
        !state.spaces.contains { $0.id == tab.spaceID }
    }
    if !orphanTabs.isEmpty {
        print("Favorites:")
        for tab in orphanTabs {
            let prefix = tab.isActive ? "  * " : "    "
            let title = tab.title.isEmpty ? "(untitled)" : tab.title
            print("\(prefix)\(title) - \(tab.url ?? "")")
        }
    }
}

func printTabs(_ tabs: [CTL.TabInfo]) {
    if tabs.isEmpty {
        print("No tabs in current space")
        return
    }
    for tab in tabs {
        printTab(tab)
    }
}

func printTab(_ tab: CTL.TabInfo) {
    let prefix = tab.isActive ? "* " : "  "
    let title = tab.title.isEmpty ? "(untitled)" : tab.title
    let url = tab.url ?? ""
    var flags: [String] = []
    if tab.isActive {
        flags.append("active")
    }
    if tab.isLoading {
        flags.append("loading")
    }
    if tab.isFavorite {
        flags.append("favorite")
    }
    if tab.isUnread == true {
        flags.append("unread")
    }
    if tab.customName != nil {
        flags.append("renamed")
    }
    if tab.groupID != nil {
        flags.append("grouped")
    }
    if tab.pageCount > 1 {
        flags.append("\(tab.pageCount) pages")
    }
    let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ", "))]"
    print("\(prefix)\(tab.id)  \(title) - \(url)\(flagStr)")
}

func printSpaces(_ spaces: [CTL.SpaceInfo]) {
    let modeWidth = spaces.map { ($0.dataStoreMode ?? "").count }.max() ?? 0
    for space in spaces {
        var markers: [String] = []
        if space.isActive {
            markers.append("active")
        }
        if space.isLocked == true {
            markers.append("locked")
        }
        if space.exposesCookies == true {
            markers.append("cookies exposed")
        }
        let markerText = markers.isEmpty ? "" : " [\(markers.joined(separator: ", "))]"
        let mode = (space.dataStoreMode ?? "").padding(toLength: modeWidth, withPad: " ", startingAt: 0)
        print("\(space.id)  \(mode)  \(space.name) (\(space.tabCount) tabs)\(markerText)")
    }
}

func printWindowInfo(_ info: CTL.WindowInfoData) {
    print("Position: \(info.x), \(info.y)")
    print("Size: \(info.width)x\(info.height)")
}

// MARK: - New Formatters

func printTabDetail(_ info: CTL.TabDetailInfo) {
    let title = info.title.isEmpty ? "(untitled)" : info.title
    print("ID: \(info.id)")
    print("Title: \(title)")
    if let customName = info.customName {
        print("Custom Name: \(customName)")
    }
    if let url = info.url {
        print("URL: \(url)")
    }
    if let spaceID = info.spaceID {
        print("Space: \(spaceID)")
    }
    if let groupID = info.groupID {
        let groupLabel = info.groupName.map { "\(groupID) (\($0))" } ?? groupID
        print("Group: \(groupLabel)")
    }

    var flags: [String] = []
    if info.isActive {
        flags.append("active")
    }
    if info.isLoading {
        flags.append("loading")
    }
    if info.isFavorite {
        flags.append("favorite")
    }
    if info.isUnread {
        flags.append("unread")
    }
    if info.isMuted {
        flags.append("muted")
    }

    if !flags.isEmpty {
        print("Flags: \(flags.joined(separator: ", "))")
    }

    print(
        "Navigation: \(info.canGoBack ? "<back" : "") \(info.canGoForward ? "forward>" : "")"
            .trimmingCharacters(in: .whitespaces),
    )

    if info.pages.count > 1 {
        print("Pages (\(info.pageCount)):")
        for page in info.pages {
            let activeMarker = page.isActive ? " [active]" : ""
            print("  \(page.id)  \(page.position)  \(page.title) - \(page.url)\(activeMarker)")
        }
    }
}

func printGroups(_ groups: [CTL.GroupInfo]) {
    if groups.isEmpty {
        print("No groups")
        return
    }
    for group in groups {
        printGroup(group)
    }
}

func printGroup(_ group: CTL.GroupInfo) {
    var details: [String] = []
    details.append(group.color)
    if let icon = group.iconName {
        details.append(icon)
    }
    details.append("\(group.tabCount) tabs")
    if group.isCollapsed {
        details.append("collapsed")
    }
    let detailStr = details.joined(separator: ", ")
    print("\(group.id)  \(group.name) [\(detailStr)]")
}

func printBookmarks(_ bookmarks: [CTL.BookmarkInfo]) {
    if bookmarks.isEmpty {
        print("No bookmarks")
        return
    }
    for bm in bookmarks {
        let fav = bm.isFavorite ? " *" : ""
        let folder = bm.folderID.map { " (folder: \($0))" } ?? ""
        print("\(bm.id)  \(bm.title) - \(bm.url)\(fav)\(folder)")
    }
}

func printBookmarkFolders(_ folders: [CTL.BookmarkFolderInfo]) {
    if folders.isEmpty {
        print("No folders")
        return
    }
    for folder in folders {
        let parent = folder.parentID.map { " (parent: \($0))" } ?? ""
        print("\(folder.id)  \(folder.name) (\(folder.bookmarkCount) bookmarks)\(parent)")
    }
}

func printHistoryEntries(_ entries: [CTL.HistoryEntryInfo]) {
    if entries.isEmpty {
        print("No history entries")
        return
    }
    for entry in entries {
        let visits = entry.visitCount > 1 ? " (\(entry.visitCount) visits)" : ""
        print("\(entry.lastVisited)  \(entry.title) - \(entry.url)\(visits)")
    }
}

func printSiteSettings(_ settings: CTL.SiteSettingsInfo) {
    print("Domain: \(settings.domain)")
    if let zoom = settings.zoom {
        print("Zoom: \(zoom)%")
    }
    if let js = settings.javascript {
        print("JavaScript: \(js ? "enabled" : "disabled")")
    }
    if let blockers = settings.contentBlockers {
        print("Content Blockers: \(blockers ? "enabled" : "disabled")")
    }
}

func printConsoleMessages(_ messages: [CTL.ConsoleMessage]) {
    if messages.isEmpty {
        print("No console messages")
        return
    }
    for msg in messages {
        let level = msg.level.uppercased().padding(toLength: 5, withPad: " ", startingAt: 0)
        print("[\(level)] \(msg.message)")
    }
}

func printNetworkEntries(_ entries: [CTL.NetworkEntry]) {
    if entries.isEmpty {
        print("No network entries")
        return
    }
    for entry in entries {
        let status = entry.status.map { "\($0)" } ?? "..."
        let duration = entry.duration.map { String(format: "%.0fms", $0) } ?? ""
        print("\(entry.method) \(status) \(entry.url) \(duration)")
    }
}

func printCookies(_ cookies: [CTL.CookieInfo]) {
    if cookies.isEmpty {
        print("No cookies")
        return
    }
    for cookie in cookies {
        var flags: [String] = []
        if cookie.isSecure {
            flags.append("secure")
        }
        if cookie.isHTTPOnly {
            flags.append("httpOnly")
        }
        flags.append(cookie.expiresDate.map { "expires \($0)" } ?? "session")
        print("\(cookie.name)=\(cookie.value ?? "•••") (\(cookie.domain)\(cookie.path)) [\(flags.joined(separator: ", "))]")
    }
}

func printStorageEntries(_ entries: [CTL.StorageEntry]) {
    if entries.isEmpty {
        print("No storage entries")
        return
    }
    for entry in entries {
        let value = entry.value.count > 80
            ? String(entry.value.prefix(80)) + "..."
            : entry.value
        print("\(entry.key) = \(value)")
    }
}

func printRecentlyClosedTabs(_ tabs: [CTL.RecentlyClosedTabInfo]) {
    if tabs.isEmpty {
        print("No recently closed tabs")
        return
    }
    for tab in tabs {
        print("\(tab.closedAt)  \(tab.title) - \(tab.url)")
    }
}

func printSettingsEntries(_ entries: [CTL.SettingEntryInfo]) {
    if entries.isEmpty {
        print("No settings found")
        return
    }

    // Group by category
    var byCategory: [String: [CTL.SettingEntryInfo]] = [:]
    for entry in entries {
        byCategory[entry.category, default: []].append(entry)
    }

    let categoryOrder = ["general", "appearance", "tabs", "privacy", "advanced"]
    let sortedCategories = byCategory.keys.sorted { a, b in
        let aIdx = categoryOrder.firstIndex(of: a) ?? Int.max
        let bIdx = categoryOrder.firstIndex(of: b) ?? Int.max
        return aIdx < bIdx
    }

    for category in sortedCategories {
        guard let entries = byCategory[category] else { continue }
        print("\(category.capitalized):")
        for entry in entries {
            print("  \(entry.key) = \(entry.value)  (\(entry.displayName))")
        }
    }
}

func printFoundElements(_ elements: [CTL.FoundElementInfo]) {
    if elements.isEmpty {
        print("No matching elements found")
        return
    }

    print("Found \(elements.count) element(s):\n")
    for element in elements {
        var line = "[\(element.ref)] \(element.tag)"
        if let role = element.role {
            line += " (\(role))"
        }
        let text = element.text.count > 80
            ? String(element.text.prefix(80)) + "..."
            : element.text
        line += " \"\(text)\""
        if let href = element.href {
            line += " -> \(href)"
        }
        if let inputType = element.inputType {
            line += " [type=\(inputType)]"
        }
        print("  \(line)")
    }
}

func printCanvas(_ info: CTL.FloatingTabsInfo) {
    print("Floating tabs: \(info.isRevealed ? "revealed" : "hidden") · \(info.tiles.filter(\.isPinned).count) pinned previews")
    for tile in info.tiles where tile.isVisible {
        print("  \(Int(tile.x)),\(Int(tile.y))  \(tile.shape.rawValue)\(tile.isPinned ? " · pinned" : "")  \(tile.title)  [\(tile.tabID)]")
    }
}

func printHealth(_ info: CTL.HealthInfo) {
    print("App Version: \(info.appVersion)")
    print("Protocol Version: \(info.protocolVersion)")
    print("Tabs: \(info.tabCount)")
    print("Windows: \(info.windowCount)")
    print("Spaces: \(info.spaceCount)")
    print("Memory: \(info.memoryUsageMB) MB")
    let hours = info.uptimeSeconds / 3_600
    let minutes = (info.uptimeSeconds % 3_600) / 60
    let seconds = info.uptimeSeconds % 60
    print("Uptime: \(hours)h \(minutes)m \(seconds)s")
}

func printExecResult(_ info: CTL.ExecResultInfo) {
    for line in info.output {
        print(line)
    }
    if !info.success {
        if let error = info.error {
            printError(error)
        }
        printInfo("Failed at step \(info.stepsExecuted)/\(info.stepsTotal)")
        _Exit(1)
    }
}

func printHumanRequest(_ info: CTL.HumanRequestInfo) {
    printInfo("Agent needs help: \(info.description)")
    printInfo("Press Enter when done...")
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func printInfo(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
