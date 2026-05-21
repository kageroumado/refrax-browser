import Foundation
import RefraxProtocol

/// Bridges Claude tool calls to `RefraxControlServer` via unified `route()` dispatch.
///
/// Each tool method constructs a `ControlRequest`, routes it through the server's
/// single dispatch point, and maps the `ControlResponse` to a `ToolOutput`.
/// This ensures the agent path shares the same multi-page tab resolution,
/// error handling, and routing logic as the CLI.
@MainActor
final class AgentToolBridge {
    private unowned let controlServer: RefraxControlServer
    private unowned let windowManager: WindowManager
    private unowned let userStyleManager: UserStyleManager
    private unowned let pagePool: WebPagePool

    /// Thought stream store for emitting tool-level activity thoughts.
    weak var thoughtStreamStore: ThoughtStreamStore?

    init(
        controlServer: RefraxControlServer,
        windowManager: WindowManager,
        userStyleManager: UserStyleManager,
        pagePool: WebPagePool,
    ) {
        self.controlServer = controlServer
        self.windowManager = windowManager
        self.userStyleManager = userStyleManager
        self.pagePool = pagePool
    }

    /// Returns the focused page ID string for split-view tabs, nil for single-page.
    private var activePageID: String? {
        guard let windowState = windowManager.activeWindowController?.windowState,
              let tab = windowState.activeTab,
              tab.pages.count > 1,
              let pageID = windowState.focusedPageID ?? windowState.activePageID
        else { return nil }
        return "\(pageID)"
    }

    // MARK: - Dispatch

    /// Executes a tool call by name with the given input parameters.
    func execute(toolName: String, input: [String: AnthropicJSONValue]) async -> ToolOutput {
        emitToolThought(toolName: toolName, input: input)

        switch toolName {
        // Page interaction
        case "read_page":
            return await executeReadPage(input)
        case "screenshot":
            return await executeScreenshot(input)
        case "navigate":
            return await executeNavigate(input)
        case "click":
            return await executeClick(input)
        case "hover":
            return await executeHover(input)
        case "type":
            return await executeType(input)
        case "scroll":
            return await executeScroll(input)
        case "form_input":
            return await executeFormInput(input)
        case "execute_javascript":
            return await executeJavaScript(input)
        // Compound tools
        case "navigate_and_read":
            return await executeNavigateAndRead(input)
        case "click_and_read":
            return await executeClickAndRead(input)
        case "fill_form":
            return await executeFillForm(input)
        case "scroll_and_read":
            return await executeScrollAndRead(input)
        case "find_elements":
            return await executeFindElements(input)
        // Tab management
        case "tabs_list":
            return await executeTabsList(input)
        case "tab_open":
            return await executeTabOpen(input)
        case "tab_close":
            return await executeTabClose(input)
        case "tab_activate":
            return await executeTabActivate(input)
        case "tab_reload":
            return await executeTabReload(input)
        case "tab_rename":
            return await executeTabRename(input)
        case "tab_reorder":
            return await executeTabReorder(input)
        case "tab_pin":
            return await executeTabPin(input)
        case "tab_duplicate":
            return await executeTabDuplicate(input)
        case "go_back":
            return await executeGoBack()
        case "go_forward":
            return await executeGoForward()
        // Tab groups
        case "group_list":
            return await executeGroupList(input)
        case "group_create":
            return await executeGroupCreate(input)
        case "group_update":
            return await executeGroupUpdate(input)
        case "group_delete":
            return await executeGroupDelete(input)
        case "tab_move_to_group":
            return await executeTabMoveToGroup(input)
        case "tab_ungroup":
            return await executeTabUngroup(input)
        // Settings
        case "settings_get":
            return await executeSettingsGet(input)
        case "settings_set":
            return await executeSettingsSet(input)
        // Program execution
        case "execute_program":
            return await executeProgram(input)
        // User styles
        case "user_style_create":
            return await executeUserStyleCreate(input)
        case "user_style_list":
            return executeUserStyleList(input)
        case "user_style_delete":
            return executeUserStyleDelete(input)
        default:
            return .error("Unknown tool: \(toolName)")
        }
    }

    // MARK: - Thought Stream

    /// Emits a descriptive thought for the tool being executed.
    private func emitToolThought(toolName: String, input: [String: AnthropicJSONValue]) {
        guard let store = thoughtStreamStore else { return }

        let (type, text): (ThoughtType, String) = switch toolName {
        case "read_page":
            (.read, "Reading page content...")
        case "screenshot":
            (.scan, "Taking a screenshot...")
        case "navigate":
            (.act, "Navigating to \(input["url"]?.stringValue ?? "page")...")
        case "click":
            (.act, "Clicking \(input["ref"]?.stringValue ?? "element")...")
        case "hover":
            (.act, "Hovering over \(input["ref"]?.stringValue ?? "element")...")
        case "type":
            (.act, "Typing text...")
        case "scroll":
            (.act, "Scrolling \(input["direction"]?.stringValue ?? "")...")
        case "form_input":
            (.act, "Filling form field...")
        case "execute_javascript":
            (.act, "Running JavaScript...")
        case "navigate_and_read":
            (.act, "Navigating to \(input["url"]?.stringValue ?? "page") and reading content...")
        case "click_and_read":
            (.act, "Clicking \(input["ref"]?.stringValue ?? input["fuzzy_text"]?.stringValue ?? "element") and reading result...")
        case "fill_form":
            (.act, "Filling form fields...")
        case "scroll_and_read":
            (.act, "Scrolling \(input["direction"]?.stringValue ?? "down") and reading content...")
        case "find_elements":
            (.scan, "Searching for elements...")
        case "tabs_list":
            (.scan, "Checking open tabs...")
        case "tab_open":
            (.act, "Opening new tab...")
        case "tab_close":
            (.act, "Closing tab...")
        case "tab_activate":
            (.act, "Switching to tab...")
        case "tab_reload":
            (.act, "Reloading page...")
        case "group_list":
            (.scan, "Checking tab groups...")
        case "group_create":
            (.act, "Creating tab group...")
        case "tab_move_to_group":
            (.act, "Moving tab to group...")
        case "tab_ungroup":
            (.act, "Removing tab from group...")
        case "settings_get":
            (.scan, "Checking setting...")
        case "settings_set":
            (.act, "Updating setting...")
        case "execute_program":
            (.act, "Running automation program...")
        case "user_style_create":
            (.act, "Creating user style...")
        case "user_style_list":
            (.scan, "Listing user styles...")
        case "user_style_delete":
            (.act, "Deleting user style...")
        default:
            (.act, "Using \(toolName)...")
        }

        store.addThought(type: type, text: text)
    }

    // MARK: - Response Mapping

    /// Maps common `.ok` / `.actionResult` / `.error` responses to `ToolOutput`.
    private func mapResponse(_ response: ControlResponse, fallback: String) -> ToolOutput {
        switch response {
        case let .ok(message):
            .success(message ?? fallback)
        case let .actionResult(info):
            .success(info.message ?? fallback)
        case let .error(info):
            .error(info.message)
        default:
            .success(fallback)
        }
    }

    // MARK: - Visual Feedback

    /// Wraps an interaction with implicit visual feedback: highlights the element before
    /// acting, shows a click animation after, then clears all feedback overlays.
    private func withVisualFeedback(
        ref: String?,
        action: () async -> ControlResponse,
    ) async -> ControlResponse {
        if let ref {
            _ = await controlServer.route(.visualHighlight(
                .init(ref: ref, style: "aboutToAct"),
            ))
            try? await Task.sleep(for: .milliseconds(300))
        }

        let response = await action()

        if let ref {
            _ = await controlServer.route(.visualClick(.init(ref: ref)))
            try? await Task.sleep(for: .milliseconds(200))
            _ = await controlServer.route(.visualClear)
        }

        return response
    }

    // MARK: - Page Interaction

    private func executeReadPage(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let scopeString = input["scope"]?.stringValue ?? "viewport"
        let scope = ControlRequest.PageContentParams.Scope(rawValue: scopeString) ?? .viewport
        let params = ControlRequest.PageContentParams(pageID: activePageID, scope: scope)

        let response = await controlServer.route(.pageContent(params))

        if case let .pageContent(content) = response {
            return .success(content)
        }
        return mapResponse(response, fallback: "Page content retrieved")
    }

    private func executeScreenshot(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let modeString = input["mode"]?.stringValue ?? "visible"
        let mode = ControlRequest.ScreenshotParams.ScreenshotMode(rawValue: modeString) ?? .visible
        let params = ControlRequest.ScreenshotParams(mode: mode, pageID: activePageID)

        let response = await controlServer.route(.screenshot(params))

        if case let .screenshot(info) = response {
            return .withImage(
                text: "Screenshot captured: \(info.width)x\(info.height)",
                mediaType: "image/png",
                base64Data: info.data,
            )
        }
        return mapResponse(response, fallback: "Screenshot captured")
    }

    private func executeNavigate(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let url = input["url"]?.stringValue else {
            return .error("Missing required parameter: url")
        }

        let params = ControlRequest.NavigateParams(url: url, pageID: activePageID)
        let response = await controlServer.route(.navigate(params))
        return mapResponse(response, fallback: "Navigated to \(url)")
    }

    private func executeClick(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let ref = input["ref"]?.stringValue
        let params = ControlRequest.ClickParams(
            ref: ref,
            x: input["x"]?.doubleValue,
            y: input["y"]?.doubleValue,
            doubleClick: input["double_click"]?.boolValue,
            rightClick: input["right_click"]?.boolValue,
            pageID: activePageID,
        )

        let response = await withVisualFeedback(ref: ref) {
            await controlServer.route(.click(params))
        }
        return mapResponse(response, fallback: "Clicked successfully")
    }

    private func executeHover(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let ref = input["ref"]?.stringValue
        let params = ControlRequest.HoverParams(
            ref: ref,
            x: input["x"]?.doubleValue,
            y: input["y"]?.doubleValue,
            pageID: activePageID,
        )

        let response = await withVisualFeedback(ref: ref) {
            await controlServer.route(.hover(params))
        }
        return mapResponse(response, fallback: "Hovered successfully")
    }

    private func executeType(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let text = input["text"]?.stringValue else {
            return .error("Missing required parameter: text")
        }

        let ref = input["element_ref"]?.stringValue
        let params = ControlRequest.TypeParams(
            text: text,
            elementRef: ref,
            pageID: activePageID,
        )

        let response = await withVisualFeedback(ref: ref) {
            await controlServer.route(.type(params))
        }
        return mapResponse(response, fallback: "Typed text successfully")
    }

    private func executeScroll(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let params = ControlRequest.ScrollParams(
            direction: input["direction"]?.stringValue,
            amount: input["amount"]?.intValue,
            ref: input["ref"]?.stringValue,
            pageID: activePageID,
        )

        let response = await controlServer.route(.scroll(params))
        return mapResponse(response, fallback: "Scrolled successfully")
    }

    private func executeFormInput(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let ref = input["ref"]?.stringValue,
              let value = input["value"]?.stringValue else {
            return .error("Missing required parameters: ref and value")
        }

        let params = ControlRequest.FormInputParams(ref: ref, value: value, pageID: activePageID)
        let response = await withVisualFeedback(ref: ref) {
            await controlServer.route(.formInput(params))
        }
        return mapResponse(response, fallback: "Form input set successfully")
    }

    private func executeJavaScript(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let script = input["script"]?.stringValue else {
            return .error("Missing required parameter: script")
        }

        let params = ControlRequest.PageExecJSParams(script: script, pageID: activePageID)
        let response = await controlServer.route(.pageExecJS(params))

        if case let .javascript(result) = response {
            return .success(result)
        }
        return mapResponse(response, fallback: "JavaScript executed")
    }

    // MARK: - Tab Management

    private func executeTabsList(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let params = ControlRequest.TabListParams(
            spaceID: input["space_id"]?.stringValue,
        )
        let response = await controlServer.route(.tabList(params))

        if case let .tabs(tabInfos) = response {
            if tabInfos.isEmpty {
                return .success("No tabs open")
            }
            let lines = tabInfos.enumerated().map { index, tab in
                let active = tab.isActive ? " [active]" : ""
                let url = tab.url ?? ""
                return "\(index + 1). \(tab.title)\(active) (id: \(tab.id))\n   \(url)"
            }
            return .success(lines.joined(separator: "\n"))
        }
        return mapResponse(response, fallback: "Tab list retrieved")
    }

    private func executeTabOpen(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let url = input["url"]?.stringValue else {
            return .error("Missing required parameter: url")
        }

        let params = ControlRequest.TabOpenParams(
            url: url,
            activate: input["activate"]?.boolValue ?? true,
        )
        let response = await controlServer.route(.tabOpen(params))

        if case let .tab(info) = response {
            return .success("Opened new tab (id: \(info.id)) — \(info.title)")
        }
        return mapResponse(response, fallback: "Tab opened")
    }

    private func executeTabClose(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }

        let params = ControlRequest.TabCloseParams(id: id)
        let response = await controlServer.route(.tabClose(params))
        return mapResponse(response, fallback: "Tab closed")
    }

    private func executeTabActivate(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }

        let params = ControlRequest.TabActivateParams(id: id)
        let response = await controlServer.route(.tabActivate(params))
        return mapResponse(response, fallback: "Switched to tab")
    }

    private func executeGoBack() async -> ToolOutput {
        let params = ControlRequest.OptionalTabIDParams(pageID: activePageID)
        let response = await controlServer.route(.tabGoBack(params))
        return mapResponse(response, fallback: "Navigated back")
    }

    private func executeGoForward() async -> ToolOutput {
        let params = ControlRequest.OptionalTabIDParams(pageID: activePageID)
        let response = await controlServer.route(.tabGoForward(params))
        return mapResponse(response, fallback: "Navigated forward")
    }

    private func executeTabReload(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let params = ControlRequest.TabReloadParams(
            pageID: activePageID,
            fromOrigin: input["bypass_cache"]?.boolValue,
        )
        let response = await controlServer.route(.tabReload(params))
        return mapResponse(response, fallback: "Page reloaded")
    }

    private func executeTabRename(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }
        let params = ControlRequest.TabRenameParams(id: id, name: input["name"]?.stringValue)
        let response = await controlServer.route(.tabRename(params))
        return mapResponse(response, fallback: "Tab renamed")
    }

    private func executeTabReorder(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue,
              let index = input["index"]?.intValue else {
            return .error("Missing required parameters: id and index")
        }
        let params = ControlRequest.TabReorderParams(id: id, index: index)
        let response = await controlServer.route(.tabReorder(params))
        return mapResponse(response, fallback: "Tab reordered")
    }

    private func executeTabPin(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }
        let params = ControlRequest.TabIDParams(id: id)
        let response = await controlServer.route(.tabPin(params))
        return mapResponse(response, fallback: "Tab pin toggled")
    }

    private func executeTabDuplicate(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }
        let params = ControlRequest.TabIDParams(id: id)
        let response = await controlServer.route(.tabDuplicate(params))

        if case let .tab(info) = response {
            return .success("Duplicated tab (new id: \(info.id)) — \(info.title)")
        }
        return mapResponse(response, fallback: "Tab duplicated")
    }

    // MARK: - Tab Groups

    private func executeGroupList(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let params = ControlRequest.GroupListParams(spaceID: input["space_id"]?.stringValue)
        let response = await controlServer.route(.groupList(params))

        if case let .groups(groupInfos) = response {
            if groupInfos.isEmpty {
                return .success("No tab groups")
            }
            let lines = groupInfos.map { group in
                var desc = "\(group.name) (id: \(group.id), color: \(group.color)"
                if let icon = group.iconName { desc += ", icon: \(icon)" }
                desc += ", \(group.tabCount) tabs)"
                return desc
            }
            return .success(lines.joined(separator: "\n"))
        }
        return mapResponse(response, fallback: "Group list retrieved")
    }

    private func executeGroupCreate(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let name = input["name"]?.stringValue else {
            return .error("Missing required parameter: name")
        }
        let params = ControlRequest.GroupCreateParams(
            name: name,
            color: input["color"]?.stringValue,
            icon: input["icon"]?.stringValue,
            spaceID: input["space_id"]?.stringValue,
        )
        let response = await controlServer.route(.groupCreate(params))

        if case let .group(info) = response {
            return .success("Created group '\(info.name)' (id: \(info.id))")
        }
        return mapResponse(response, fallback: "Group created")
    }

    private func executeGroupUpdate(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }

        var updates: [String] = []

        if let name = input["name"]?.stringValue {
            let response = await controlServer.route(.groupRename(ControlRequest.GroupRenameParams(id: id, name: name)))
            if case let .error(info) = response { return .error(info.message) }
            updates.append("name → '\(name)'")
        }
        if let color = input["color"]?.stringValue {
            let response = await controlServer.route(.groupSetColor(ControlRequest.GroupSetColorParams(id: id, color: color)))
            if case let .error(info) = response { return .error(info.message) }
            updates.append("color → '\(color)'")
        }
        if let icon = input["icon"]?.stringValue {
            let response = await controlServer.route(.groupSetIcon(ControlRequest.GroupSetIconParams(id: id, icon: icon)))
            if case let .error(info) = response { return .error(info.message) }
            updates.append("icon → '\(icon)'")
        }

        if updates.isEmpty {
            return .error("No update fields provided (name, color, or icon)")
        }
        return .success("Group updated: \(updates.joined(separator: ", "))")
    }

    private func executeGroupDelete(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }
        let params = ControlRequest.GroupDeleteParams(id: id, closeTabs: input["close_tabs"]?.boolValue)
        let response = await controlServer.route(.groupDelete(params))
        return mapResponse(response, fallback: "Group deleted")
    }

    private func executeTabMoveToGroup(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue,
              let groupID = input["group_id"]?.stringValue else {
            return .error("Missing required parameters: id and group_id")
        }
        let params = ControlRequest.TabMoveToGroupParams(id: id, groupID: groupID)
        let response = await controlServer.route(.tabMoveToGroup(params))
        return mapResponse(response, fallback: "Tab moved to group")
    }

    private func executeTabUngroup(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let id = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }
        let params = ControlRequest.TabIDParams(id: id)
        let response = await controlServer.route(.tabRemoveFromGroup(params))
        return mapResponse(response, fallback: "Tab removed from group")
    }

    // MARK: - Compound Tools

    private func executeNavigateAndRead(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let url = input["url"]?.stringValue else {
            return .error("Missing required parameter: url")
        }

        let scopeString = input["scope"]?.stringValue
        let scope = scopeString.flatMap { ControlRequest.PageContentParams.Scope(rawValue: $0) }

        let params = ControlRequest.NavigateAndReadParams(
            url: url,
            scope: scope,
            timeout: input["timeout"]?.intValue,
            tabID: input["tab_id"]?.stringValue,
            pageID: input["page_id"]?.stringValue ?? activePageID,
        )

        let response = await controlServer.route(.navigateAndRead(params))

        if case let .pageContent(content) = response {
            return .success(content)
        }
        return mapResponse(response, fallback: "Navigated to \(url) and read content")
    }

    private func executeClickAndRead(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let ref = input["ref"]?.stringValue
        let scopeString = input["scope"]?.stringValue
        let scope = scopeString.flatMap { ControlRequest.PageContentParams.Scope(rawValue: $0) }

        let params = ControlRequest.ClickAndReadParams(
            ref: ref,
            fuzzyText: input["fuzzy_text"]?.stringValue,
            x: input["x"]?.doubleValue,
            y: input["y"]?.doubleValue,
            scope: scope,
            waitForNavigation: input["wait_for_navigation"]?.boolValue,
            timeout: input["timeout"]?.intValue,
            tabID: input["tab_id"]?.stringValue,
            pageID: input["page_id"]?.stringValue ?? activePageID,
        )

        let response = await withVisualFeedback(ref: ref) {
            await controlServer.route(.clickAndRead(params))
        }

        if case let .pageContent(content) = response {
            return .success(content)
        }
        return mapResponse(response, fallback: "Clicked and read content")
    }

    private func executeFillForm(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard case let .array(fieldsArray) = input["fields"] else {
            return .error("Missing required parameter: fields (array)")
        }

        var fields: [ControlRequest.FillFormParams.FieldEntry] = []
        for fieldValue in fieldsArray {
            guard case let .object(fieldObj) = fieldValue,
                  case let .string(ref) = fieldObj["ref"],
                  case let .string(value) = fieldObj["value"]
            else {
                return .error("Each field must have 'ref' (string) and 'value' (string)")
            }
            fields.append(.init(ref: ref, value: value))
        }

        let params = ControlRequest.FillFormParams(
            fields: fields,
            submitRef: input["submit_ref"]?.stringValue,
            tabID: input["tab_id"]?.stringValue,
            pageID: input["page_id"]?.stringValue ?? activePageID,
        )

        let response = await controlServer.route(.fillForm(params))
        return mapResponse(response, fallback: "Form filled successfully")
    }

    private func executeScrollAndRead(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let scopeString = input["scope"]?.stringValue
        let scope = scopeString.flatMap { ControlRequest.PageContentParams.Scope(rawValue: $0) }

        let params = ControlRequest.ScrollAndReadParams(
            direction: input["direction"]?.stringValue,
            amount: input["amount"]?.intValue,
            ref: input["ref"]?.stringValue,
            scope: scope,
            tabID: input["tab_id"]?.stringValue,
            pageID: input["page_id"]?.stringValue ?? activePageID,
        )

        let response = await controlServer.route(.scrollAndRead(params))

        if case let .pageContent(content) = response {
            return .success(content)
        }
        return mapResponse(response, fallback: "Scrolled and read content")
    }

    private func executeFindElements(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let params = ControlRequest.FindElementsParams(
            text: input["text"]?.stringValue,
            role: input["role"]?.stringValue,
            tag: input["tag"]?.stringValue,
            limit: input["limit"]?.intValue,
            tabID: input["tab_id"]?.stringValue,
            pageID: input["page_id"]?.stringValue ?? activePageID,
        )

        let response = await controlServer.route(.findElements(params))

        if case let .foundElements(elements) = response {
            if elements.isEmpty {
                return .success("No matching elements found")
            }
            let lines = elements.map { element in
                var desc = "\(element.ref): <\(element.tag)>"
                if let role = element.role { desc += " [\(role)]" }
                if !element.text.isEmpty { desc += " \"\(element.text)\"" }
                if let href = element.href { desc += " → \(href)" }
                if let inputType = element.inputType { desc += " (type: \(inputType))" }
                return desc
            }
            return .success("Found \(elements.count) element(s):\n\(lines.joined(separator: "\n"))")
        }
        return mapResponse(response, fallback: "Element search completed")
    }

    // MARK: - Program Execution

    private func executeProgram(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        let program = input["program"]?.stringValue ?? ""
        let timeout = input["timeout"]?.intValue
        let verbose = input["verbose"]?.boolValue ?? false

        let params = ControlRequest.ExecProgramParams(
            program: program,
            timeout: timeout,
            verbose: verbose,
            dryRun: false,
            tabID: nil,
            pageID: nil,
            policy: .default,
        )

        let response = await controlServer.route(.execProgram(params))

        switch response {
        case let .execResult(info):
            if info.success {
                let outputText = info.output.joined(separator: "\n")
                return .success(outputText.isEmpty ? "Program completed successfully (\(info.stepsExecuted) steps)" : outputText)
            } else {
                return .error(info.error ?? "Program execution failed at step \(info.stepsExecuted)/\(info.stepsTotal)")
            }
        case let .error(errorInfo):
            return .error(errorInfo.message)
        default:
            return .error("Unexpected response from program execution")
        }
    }

    // MARK: - Settings

    private func executeSettingsGet(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let key = input["key"]?.stringValue else {
            return .error("Missing required parameter: key")
        }

        let response = await controlServer.route(.settingsGet(.init(key: key)))

        if case let .settingsEntries(entries) = response, let entry = entries.first {
            return .success("\(entry.displayName): \(entry.value)")
        }
        return mapResponse(response, fallback: "Setting retrieved")
    }

    private func executeSettingsSet(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let key = input["key"]?.stringValue else {
            return .error("Missing required parameter: key")
        }
        guard let value = input["value"]?.stringValue else {
            return .error("Missing required parameter: value")
        }

        let response = await controlServer.route(.settingsSet(.init(key: key, value: value)))
        return mapResponse(response, fallback: "Setting updated")
    }

    // MARK: - User Styles

    private func executeUserStyleCreate(_ input: [String: AnthropicJSONValue]) async -> ToolOutput {
        guard let css = input["css"]?.stringValue, !css.isEmpty else {
            return .error("Missing required parameter: css")
        }

        let name = input["name"]?.stringValue ?? "Agent Style"
        let isGlobal = input["is_global"]?.boolValue ?? false

        var domainPatterns: [String] = []
        if let patterns = input["domain"]?.stringValue {
            domainPatterns = [patterns]
        } else if case let .array(arr) = input["domain"] {
            domainPatterns = arr.compactMap(\.stringValue)
        }

        let style = UserStyle(
            name: name,
            css: css,
            domainPatterns: domainPatterns,
            isGlobal: isGlobal,
        )
        userStyleManager.add(style)

        // Inject immediately into the current page without reload
        await injectStyleIntoActivePage(style)

        var desc = "Created user style '\(name)' (id: \(style.id.uuidString))"
        if isGlobal {
            desc += " — applies to all sites"
        } else if !domainPatterns.isEmpty {
            desc += " — applies to \(domainPatterns.joined(separator: ", "))"
        }
        desc += ". Applied immediately to current page."
        return .success(desc)
    }

    private func executeUserStyleList(_: [String: AnthropicJSONValue]) -> ToolOutput {
        let styles = userStyleManager.styles

        if styles.isEmpty {
            return .success("No user styles installed")
        }

        let lines = styles.map { style in
            let status = style.isEnabled ? "enabled" : "disabled"
            let scope: String = if style.isGlobal {
                "global"
            } else if !style.domainPatterns.isEmpty {
                style.domainPatterns.joined(separator: ", ")
            } else {
                "no patterns"
            }
            return "\(style.displayName) [\(status)] (id: \(style.id.uuidString)) — \(scope)"
        }
        return .success("User styles:\n\(lines.joined(separator: "\n"))")
    }

    private func executeUserStyleDelete(_ input: [String: AnthropicJSONValue]) -> ToolOutput {
        guard let idString = input["id"]?.stringValue else {
            return .error("Missing required parameter: id")
        }

        guard let uuid = UUID(uuidString: idString),
              let style = userStyleManager.style(for: uuid)
        else {
            return .error("User style not found: \(idString)")
        }

        let name = style.displayName
        userStyleManager.delete(style)
        return .success("Deleted user style '\(name)'")
    }

    /// Injects a style's CSS into the currently active page via JavaScript.
    ///
    /// This provides immediate visual feedback without requiring a page reload.
    /// The style is also persisted via the manager, so future page loads get it
    /// through the normal WKUserScript injection pipeline.
    private func injectStyleIntoActivePage(_ style: UserStyle) async {
        guard let windowState = windowManager.activeWindowController?.windowState,
              let tab = windowState.activeTab,
              let webPage = pagePool.page(for: tab.activePage)
        else { return }

        await userStyleManager.previewStyle(style.css, id: style.id, in: webPage)
    }
}

// MARK: - AnthropicJSONValue Helpers

extension AnthropicJSONValue {
    var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case let .number(v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case let .number(v) = self { return Int(v) }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(v) = self { return v }
        return nil
    }
}
