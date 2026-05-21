import CoreGraphics
import Foundation
import RefraxProtocol

/// Interprets and executes browser automation programs written in Refrax's DSL.
///
/// Programs are line-oriented text with variables, conditionals, loops,
/// try/catch, emit output, string interpolation, and predicate-based element queries.
/// Commands execute against a ``RefraxControlServer`` via `.route()` calls.
///
/// ## Example Program
/// ```
/// navigate "https://example.com" --wait
/// $content = read_page viewport
/// $link = find $content where role=link text contains "About"
/// click $link
/// emit "Clicked: ${link.text}"
/// ```
@MainActor
final class ProgramInterpreter {
    private unowned let controlServer: RefraxControlServer
    private unowned let visualFeedback: VisualFeedbackManager
    private unowned let humanIntervention: HumanInterventionManager

    // MARK: - Execution State

    private var variables: [String: ProgramValue] = [:]
    private var output: [String] = []
    private var stepCount = 0
    private var totalSteps = 0
    private var deadline: ContinuousClock.Instant = .now
    private var verbose = false
    private var dryRun = false
    private var tabID: String?
    private var pageID: String?

    private var policy: ProgramSecurityPolicy = .permissive
    private var navigationCount = 0
    private var interactionCount = 0
    private var pageReadCount = 0

    /// Callback invoked when `request_human` suspends the interpreter.
    /// The caller (control server) can use this to send an early response to the CLI.
    var onHumanRequest: ((_ token: String, _ description: String) -> Void)?

    init(controlServer: RefraxControlServer, visualFeedback: VisualFeedbackManager, humanIntervention: HumanInterventionManager) {
        self.controlServer = controlServer
        self.visualFeedback = visualFeedback
        self.humanIntervention = humanIntervention
    }

    // MARK: - Public API

    /// Executes a program and returns the result.
    ///
    /// - Parameters:
    ///   - program: The DSL program text.
    ///   - timeout: Maximum execution time in seconds.
    ///   - verbose: If true, emit diagnostic info for each step.
    ///   - dryRun: If true, count steps without executing.
    ///   - tabID: Default tab ID for commands.
    ///   - pageID: Default page ID for commands.
    ///   - policy: Security policy to enforce. nil defaults to `.permissive`.
    /// - Returns: Execution result with output, success status, and step counts.
    func execute(
        program: String,
        timeout: TimeInterval = 60,
        verbose: Bool = false,
        dryRun: Bool = false,
        tabID: String? = nil,
        pageID: String? = nil,
        policy: ProgramSecurityPolicy? = nil,
    ) async -> CTL.ExecResultInfo {
        let effectivePolicy = policy ?? .permissive
        self.policy = effectivePolicy
        variables = [:]
        output = []
        stepCount = 0
        totalSteps = 0
        navigationCount = 0
        interactionCount = 0
        pageReadCount = 0
        self.verbose = verbose
        self.dryRun = dryRun
        self.tabID = tabID
        self.pageID = pageID

        let effectiveTimeout = min(timeout, effectivePolicy.maxExecutionTime)
        deadline = .now + .seconds(effectiveTimeout)

        let lines = program.components(separatedBy: "\n")
        totalSteps = countExecutableLines(lines)

        let violations = ProgramSecurityAnalyzer.validate(program: program, policy: effectivePolicy)
        if !violations.isEmpty {
            let violationLines = violations.map { v in
                var msg = "[POLICY VIOLATION] \(v.message)"
                if let line = v.line { msg += " (line \(line))" }
                return msg
            }
            return CTL.ExecResultInfo(
                output: violationLines,
                success: false,
                error: "Program rejected by security policy: \(violations.count) violation(s)",
                stepsExecuted: 0,
                stepsTotal: totalSteps,
            )
        }

        if dryRun {
            return CTL.ExecResultInfo(
                output: ["Dry run: \(totalSteps) steps would execute"],
                success: true,
                stepsExecuted: 0,
                stepsTotal: totalSteps,
            )
        }

        visualFeedback.activate()
        defer { visualFeedback.deactivate() }

        var errorMessage: String?
        var lineIndex = 0

        do {
            while lineIndex < lines.count {
                guard ContinuousClock.now < deadline else {
                    errorMessage = "Program timed out after \(Int(effectiveTimeout))s"
                    break
                }

                let result = try await executeLine(lines: lines, index: lineIndex)
                lineIndex = result.nextIndex
            }
        } catch let error as ProgramError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }

        return CTL.ExecResultInfo(
            output: output,
            success: errorMessage == nil,
            error: errorMessage,
            stepsExecuted: stepCount,
            stepsTotal: totalSteps,
        )
    }

    // MARK: - Line Execution

    /// Result of executing a single line or block.
    private struct LineResult {
        let nextIndex: Int
    }

    /// Executes a single line (or block) and returns the next line index.
    private func executeLine(lines: [String], index: Int) async throws -> LineResult {
        let line = lines[index].trimmingCharacters(in: .whitespaces)

        if line.isEmpty || line.hasPrefix("#") {
            return LineResult(nextIndex: index + 1)
        }

        stepCount += 1

        if verbose {
            output.append("[step \(stepCount)] \(line)")
        }

        if let assignMatch = line.firstMatch(of: /^\$([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$/) {
            let varName = String(assignMatch.1)
            let commandLine = String(assignMatch.2)
            let value = try await executeCommand(commandLine)
            variables[varName] = value
            return LineResult(nextIndex: index + 1)
        }

        if line.hasPrefix("if ") {
            return try await executeIf(lines: lines, index: index)
        }

        if line.hasPrefix("for ") {
            return try await executeFor(lines: lines, index: index)
        }

        if line.hasPrefix("try"), line.hasSuffix("{") {
            return try await executeTryCatch(lines: lines, index: index)
        }

        if line.hasPrefix("emit_json ") {
            let json = String(line.dropFirst("emit_json ".count))
            output.append(interpolate(json))
            return LineResult(nextIndex: index + 1)
        }

        if line.hasPrefix("emit ") {
            let message = extractQuotedString(from: String(line.dropFirst("emit ".count))) ?? String(line.dropFirst("emit ".count))
            output.append(interpolate(message))
            return LineResult(nextIndex: index + 1)
        }

        _ = try await executeCommand(line)
        return LineResult(nextIndex: index + 1)
    }

    // MARK: - Command Dispatch

    /// Executes a single command and returns the resulting value.
    @discardableResult
    private func executeCommand(_ commandLine: String) async throws -> ProgramValue {
        let line = commandLine.trimmingCharacters(in: .whitespaces)
        let parts = tokenize(line)
        guard let command = parts.first else {
            return .string("")
        }

        switch command {
        // Navigation
        case "navigate":
            try checkNavigationLimit()
            return try await executeNavigate(parts: parts)
        case "go_back":
            try checkNavigationLimit()
            return try await executeRoute(.tabGoBack(ControlRequest.OptionalTabIDParams(tabID: tabID, pageID: pageID)))
        case "go_forward":
            try checkNavigationLimit()
            return try await executeRoute(.tabGoForward(ControlRequest.OptionalTabIDParams(tabID: tabID, pageID: pageID)))
        case "reload":
            try checkNavigationLimit()
            let fromOrigin = parts.contains("--from-origin")
            return try await executeRoute(.tabReload(ControlRequest.TabReloadParams(tabID: tabID, pageID: pageID, fromOrigin: fromOrigin)))
        // Reading
        case "read_page":
            try checkPageReadLimit()
            return try await executeReadPage(parts: parts)
        case "screenshot":
            try checkPageReadLimit()
            return try await executeScreenshot(parts: parts)
        // Element queries
        case "find":
            return try await executeFind(parts: parts, findAll: false)
        case "find_all":
            return try await executeFind(parts: parts, findAll: true)
        case "exists":
            return try await executeExists(parts: parts)
        case "count":
            return try await executeCount(parts: parts)
        // Interaction (DOM-mutating commands invalidate page content cache)
        case "click":
            return try await executeMutatingInteraction { try await self.executeClick(parts: parts) }
        case "type":
            return try await executeMutatingInteraction { try await self.executeType(parts: parts) }
        case "fill":
            return try await executeMutatingInteraction { try await self.executeFill(parts: parts) }
        case "fill_form":
            return try await executeMutatingInteraction { try await self.executeFillForm(parts: parts, fullLine: line) }
        case "hover":
            try checkInteractionLimit()
            return try await executeHover(parts: parts)
        case "select":
            return try await executeMutatingInteraction { try await self.executeSelect(parts: parts) }
        case "press_key":
            return try await executeMutatingInteraction { try await self.executePressKey(parts: parts) }
        // Scroll
        case "scroll":
            return try await executeScroll(parts: parts)
        // Flow control
        case "wait":
            return try await executeWait(parts: parts)
        case "wait_for_navigation":
            return try await executeWaitForNavigation(parts: parts)
        // JavaScript
        case "page_exec":
            guard policy.allowJavaScript else {
                throw ProgramError("Security policy: JavaScript execution is not allowed")
            }
            return try await executePageExec(parts: parts)
        // Human-in-the-loop
        case "request_human":
            try checkInteractionLimit()
            return try await executeRequestHuman(parts: parts)
        // Cookie consent
        case "dismiss_cookies":
            return try await executeMutatingInteraction { try await self.executeDismissCookies(parts: parts) }
        default:
            throw ProgramError("Unknown command: \(command)")
        }
    }

    // MARK: - Navigation Commands

    private func executeNavigate(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 2 else {
            throw ProgramError("navigate requires a URL argument")
        }
        let url = interpolate(parts[1])
        let hasWait = parts.contains("--wait")
        let timeout = extractIntFlag(parts: parts, flag: "--timeout")

        try checkDomainPolicy(urlString: url)

        if hasWait {
            let params = ControlRequest.NavigateAndWaitParams(url: url, tabID: tabID, pageID: pageID, timeout: timeout)
            visualFeedback.setCursorState(.thinking)
            let result = try await executeRoute(.navigateAndWait(params))
            visualFeedback.setCursorState(.idle)

            try await checkCurrentURLAgainstPolicy()

            return result
        } else {
            let params = ControlRequest.NavigateParams(url: url, tabID: tabID, pageID: pageID)
            visualFeedback.setCursorState(.thinking)
            let result = try await executeRoute(.navigate(params))
            visualFeedback.setCursorState(.idle)
            return result
        }
    }

    // MARK: - Read Commands

    private func executeReadPage(parts: [String]) async throws -> ProgramValue {
        let scopeStr = parts.count >= 2 ? parts[1] : "viewport"
        let scope: ControlRequest.PageContentParams.Scope = switch scopeStr {
        case "full": .full
        case "text": .text
        case "html": .html
        case "main": .mainContent
        default: .viewport
        }

        visualFeedback.setCursorState(.reading)
        let params = ControlRequest.PageContentParams(tabID: tabID, pageID: pageID, scope: scope)
        let response = await controlServer.route(.pageContent(params))
        visualFeedback.setCursorState(.idle)

        switch response {
        case let .pageContent(text):
            return .string(text)
        case let .error(info):
            throw ProgramError("read_page failed: \(info.message)")
        default:
            return .string("")
        }
    }

    private func executeScreenshot(parts: [String]) async throws -> ProgramValue {
        var outputPath: String?
        if let arrowIndex = parts.firstIndex(of: "->"), arrowIndex + 1 < parts.count {
            outputPath = interpolate(parts[arrowIndex + 1])
        }
        let params = ControlRequest.ScreenshotParams(mode: .visible, tabID: tabID, pageID: pageID, outputPath: outputPath)
        let response = await controlServer.route(.screenshot(params))

        switch response {
        case let .screenshot(info):
            return .string("Screenshot captured (\(info.width)x\(info.height))")
        case let .error(info):
            throw ProgramError("screenshot failed: \(info.message)")
        default:
            return .string("screenshot saved")
        }
    }

    // MARK: - Element Query Commands

    private func executeFind(parts: [String], findAll: Bool) async throws -> ProgramValue {
        guard parts.count >= 4, parts[2] == "where" else {
            throw ProgramError("\(parts[0]) requires: \(parts[0]) $content where PREDICATE")
        }

        let contentVarName = stripDollar(parts[1])
        let predicates = parsePredicates(Array(parts[3...]))

        if let contentValue = variables[contentVarName], case let .content(tree) = contentValue {
            let matches = queryElements(content: tree, predicates: predicates)
            if findAll {
                return .elementList(matches)
            } else {
                guard let first = matches.first else {
                    throw ProgramError("No element matching predicates found")
                }
                return .element(first)
            }
        }

        let serverParams = buildFindElementsParams(from: predicates)
        let response = await controlServer.route(.findElements(serverParams))

        switch response {
        case let .foundElements(elements):
            let handles = elements.map { elementInfoToHandle($0) }
            if findAll {
                return .elementList(handles)
            } else {
                guard let first = handles.first else {
                    throw ProgramError("No element matching predicates found")
                }
                return .element(first)
            }
        case let .error(info):
            throw ProgramError("find failed: \(info.message)")
        default:
            throw ProgramError("Unexpected response from findElements")
        }
    }

    private func executeExists(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 4, parts[2] == "where" else {
            throw ProgramError("exists requires: exists $content where PREDICATE")
        }

        let contentVarName = stripDollar(parts[1])
        let predicates = parsePredicates(Array(parts[3...]))

        if let contentValue = variables[contentVarName], case let .content(tree) = contentValue {
            let matches = queryElements(content: tree, predicates: predicates)
            return .bool(!matches.isEmpty)
        }

        let serverParams = buildFindElementsParams(from: predicates)
        let response = await controlServer.route(.findElements(serverParams))

        if case let .foundElements(elements) = response {
            return .bool(!elements.isEmpty)
        }
        return .bool(false)
    }

    private func executeCount(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 4, parts[2] == "where" else {
            throw ProgramError("count requires: count $content where PREDICATE")
        }

        let contentVarName = stripDollar(parts[1])
        let predicates = parsePredicates(Array(parts[3...]))

        if let contentValue = variables[contentVarName], case let .content(tree) = contentValue {
            let matches = queryElements(content: tree, predicates: predicates)
            return .string(String(matches.count))
        }

        let serverParams = buildFindElementsParams(from: predicates)
        let response = await controlServer.route(.findElements(serverParams))

        if case let .foundElements(elements) = response {
            return .string(String(elements.count))
        }
        return .string("0")
    }

    // MARK: - Interaction Commands

    private func executeClick(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 2 else {
            throw ProgramError("click requires a target (element variable, ref, or quoted text)")
        }

        let target = parts[1]

        if target.hasPrefix("$") {
            let value = try resolveValue(target)
            if case let .element(el) = value {
                return try await performClickOnElement(el)
            }
            return try await performClickOnRef(value.stringValue)
        }

        if target.hasPrefix("\"") {
            let text = extractQuotedString(from: parts.dropFirst().joined(separator: " ")) ?? target
            let params = ControlRequest.ClickAndReadParams(fuzzyText: interpolate(text), tabID: tabID, pageID: pageID)
            return try await executeRoute(.clickAndRead(params))
        }

        return try await performClickOnRef(interpolate(target))
    }

    private func performClickOnElement(_ element: ElementHandle) async throws -> ProgramValue {
        try await withVisualFeedback(element: element, action: .clicking) {
            let params = ControlRequest.ClickParams(ref: element.ref, tabID: tabID, pageID: pageID)
            return await controlServer.route(.click(params))
        }
    }

    private func performClickOnRef(_ ref: String) async throws -> ProgramValue {
        // Try to get element rect for visual feedback
        if let element = await resolveRefToElement(ref) {
            return try await withVisualFeedback(element: element, action: .clicking) {
                let params = ControlRequest.ClickParams(ref: ref, tabID: self.tabID, pageID: self.pageID)
                return await self.controlServer.route(.click(params))
            }
        }

        // Fallback: click without visual feedback if element can't be resolved
        let params = ControlRequest.ClickParams(ref: ref, tabID: tabID, pageID: pageID)
        let response = await controlServer.route(.click(params))
        return try mapResponse(response)
    }

    private func executeType(parts: [String]) async throws -> ProgramValue {
        let fullArgs = parts.dropFirst().joined(separator: " ")
        guard let text = extractQuotedString(from: fullArgs) else {
            throw ProgramError("type requires quoted text: type \"text\"")
        }

        var elementRef: String?
        if let intoIndex = parts.firstIndex(of: "into"), intoIndex + 1 < parts.count {
            elementRef = try resolveRef(parts[intoIndex + 1])
        }

        let params = ControlRequest.TypeParams(text: interpolate(text), elementRef: elementRef, tabID: tabID, pageID: pageID)
        return try await executeRoute(.type(params))
    }

    private func executeFill(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 3 else {
            throw ProgramError("fill requires: fill $element \"value\"")
        }

        let valueStr = parts.dropFirst(2).joined(separator: " ")
        guard let value = extractQuotedString(from: valueStr) else {
            throw ProgramError("fill requires a quoted value")
        }
        let interpolatedValue = interpolate(value)

        let target = parts[1]
        let resolved = try resolveValue(target)

        if case let .element(el) = resolved {
            try checkSensitiveField(el)
            return try await withVisualFeedback(element: el, action: .clicking) {
                let params = ControlRequest.FormInputParams(ref: el.ref, value: interpolatedValue, tabID: tabID, pageID: pageID)
                return await controlServer.route(.formInput(params))
            }
        }

        let ref = resolved.stringValue
        if policy.sensitiveFieldPolicy != .allow, let element = await resolveRefToElement(ref) {
            try checkSensitiveField(element)
        }

        let params = ControlRequest.FormInputParams(ref: ref, value: interpolatedValue, tabID: tabID, pageID: pageID)
        return try await executeRoute(.formInput(params))
    }

    private func executeFillForm(parts _: [String], fullLine: String) async throws -> ProgramValue {
        guard let braceStart = fullLine.firstIndex(of: "{"),
              let braceEnd = fullLine.lastIndex(of: "}") else {
            throw ProgramError("fill_form requires fields in { }")
        }

        let fieldsStr = String(fullLine[fullLine.index(after: braceStart) ..< braceEnd])
        let fieldEntries = fieldsStr.components(separatedBy: ",").compactMap { entry -> ControlRequest.FillFormParams.FieldEntry? in
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard let colonIdx = trimmed.firstIndex(of: ":") else { return nil }
            let key = trimmed[trimmed.startIndex ..< colonIdx].trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            let ref: String
            if key.hasPrefix("$") {
                let varName = stripDollar(key)
                if let varValue = variables[varName], case let .element(el) = varValue {
                    ref = el.ref
                } else {
                    ref = varName
                }
            } else {
                ref = interpolate(key)
            }

            let value = extractQuotedString(from: rawValue) ?? rawValue
            return ControlRequest.FillFormParams.FieldEntry(ref: ref, value: interpolate(value))
        }

        var submitRef: String?
        let afterBrace = String(fullLine[fullLine.index(after: braceEnd)...]).trimmingCharacters(in: .whitespaces)
        if afterBrace.hasPrefix("submit") {
            let submitParts = afterBrace.components(separatedBy: " ")
            if submitParts.count >= 2 {
                let submitTarget = submitParts[1]
                if submitTarget.hasPrefix("$") {
                    let varName = stripDollar(submitTarget)
                    if let varValue = variables[varName], case let .element(el) = varValue {
                        submitRef = el.ref
                    } else {
                        submitRef = variables[varName]?.stringValue
                    }
                } else {
                    submitRef = interpolate(submitTarget)
                }
            }
        }

        let params = ControlRequest.FillFormParams(fields: fieldEntries, submitRef: submitRef, tabID: tabID, pageID: pageID)
        return try await executeRoute(.fillForm(params))
    }

    private func executeHover(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 2 else {
            throw ProgramError("hover requires a target")
        }

        let target = parts[1]
        let value = try resolveValue(target)

        if case let .element(el) = value {
            return try await withVisualFeedback(element: el, action: .hovering) {
                let params = ControlRequest.HoverParams(ref: el.ref, tabID: tabID, pageID: pageID)
                return await controlServer.route(.hover(params))
            }
        }

        let params = ControlRequest.HoverParams(ref: value.stringValue, tabID: tabID, pageID: pageID)
        return try await executeRoute(.hover(params))
    }

    private func executeSelect(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 3 else {
            throw ProgramError("select requires: select $element \"option\"")
        }

        let optionStr = parts.dropFirst(2).joined(separator: " ")
        guard let option = extractQuotedString(from: optionStr) else {
            throw ProgramError("select requires a quoted option value")
        }

        let ref = try resolveRef(parts[1])
        let params = ControlRequest.FormInputParams(ref: ref, value: interpolate(option), tabID: tabID, pageID: pageID)
        return try await executeRoute(.formInput(params))
    }

    private func executePressKey(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 2 else {
            throw ProgramError("press_key requires a key spec: press_key \"Return\"")
        }
        let keySpec = extractQuotedString(from: parts.dropFirst().joined(separator: " ")) ?? parts[1]
        let params = ControlRequest.HotkeyParams(keys: interpolate(keySpec))
        return try await executeRoute(.hotkey(params))
    }

    // MARK: - Cookie Consent

    private func executeDismissCookies(parts: [String]) async throws -> ProgramValue {
        let params = ControlRequest.DismissCookiesParams(
            acceptAll: parts.contains("--accept-all"),
            tabID: tabID,
            pageID: pageID,
        )
        return try await executeRoute(.dismissCookies(params))
    }

    // MARK: - Human-in-the-Loop

    private func executeRequestHuman(parts: [String]) async throws -> ProgramValue {
        guard parts.count >= 2 else {
            throw ProgramError("request_human requires a description: request_human \"Please solve the captcha\"")
        }
        let description = extractQuotedString(from: parts.dropFirst().joined(separator: " ")) ?? parts[1]
        let interpolatedDesc = interpolate(description)

        output.append("[HUMAN_REQUESTED: \(interpolatedDesc)]")

        let requestID = UUID()
        let token = requestID.uuidString

        // Notify the control server (for CLI path)
        onHumanRequest?(token, interpolatedDesc)

        visualFeedback.setCursorState(.thinking)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            humanIntervention.register(
                id: requestID,
                token: token,
                description: interpolatedDesc,
                continuation: continuation,
            )
        }

        visualFeedback.setCursorState(.idle)
        return .string("Human intervention completed")
    }

    // MARK: - Scroll

    private func executeScroll(parts: [String]) async throws -> ProgramValue {
        let direction = parts.count >= 2 ? parts[1] : "down"
        let amount = extractIntFlag(parts: parts, flag: "--amount")

        var ref: String?
        if let refIndex = parts.firstIndex(of: "--ref"), refIndex + 1 < parts.count {
            ref = try resolveRef(parts[refIndex + 1])
        }

        let params = ControlRequest.ScrollParams(direction: direction, amount: amount, ref: ref, tabID: tabID, pageID: pageID)
        return try await executeRoute(.scroll(params))
    }

    // MARK: - Wait Commands

    private func executeWait(parts: [String]) async throws -> ProgramValue {
        let seconds: Double = if parts.count >= 2, let s = Double(parts[1]) {
            min(s, 30)
        } else {
            1
        }
        try await Task.sleep(for: .seconds(seconds))
        return .string("waited \(seconds)s")
    }

    private func executeWaitForNavigation(parts: [String]) async throws -> ProgramValue {
        let timeout = extractIntFlag(parts: parts, flag: "--timeout")
        let params = ControlRequest.TabWaitLoadedParams(tabID: tabID, pageID: pageID, timeout: timeout)
        visualFeedback.setCursorState(.thinking)
        let result = try await executeRoute(.tabWaitLoaded(params))
        visualFeedback.setCursorState(.idle)
        return result
    }

    // MARK: - JavaScript Execution

    private func executePageExec(parts: [String]) async throws -> ProgramValue {
        let scriptStr = parts.dropFirst().joined(separator: " ")
        guard let script = extractQuotedString(from: scriptStr) else {
            throw ProgramError("page_exec requires a quoted script")
        }
        let params = ControlRequest.PageExecJSParams(script: interpolate(script), tabID: tabID, pageID: pageID)
        let response = await controlServer.route(.pageExecJS(params))

        switch response {
        case let .javascript(result):
            return .string(result)
        case let .ok(message):
            return .string(message ?? "ok")
        case let .error(info):
            throw ProgramError("page_exec failed: \(info.message)")
        default:
            return .string("")
        }
    }

    // MARK: - Control Flow: If/Else

    private func executeIf(lines: [String], index: Int) async throws -> LineResult {
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        guard line.hasSuffix("{") else {
            throw ProgramError("if block must end with '{'")
        }

        let conditionStr = String(line.dropFirst(3).dropLast(1)).trimmingCharacters(in: .whitespaces)
        let conditionResult = evaluateCondition(conditionStr)
        let bodyStart = index + 1
        let blockEnd = findBlockEnd(lines: lines, from: bodyStart)

        if conditionResult {
            var lineIdx = bodyStart
            while lineIdx < blockEnd.bodyEnd {
                let result = try await executeLine(lines: lines, index: lineIdx)
                lineIdx = result.nextIndex
            }
            return LineResult(nextIndex: blockEnd.afterBlock)
        }

        if let elseInfo = blockEnd.elseBlock {
            var lineIdx = elseInfo.bodyStart
            while lineIdx < elseInfo.bodyEnd {
                let result = try await executeLine(lines: lines, index: lineIdx)
                lineIdx = result.nextIndex
            }
            return LineResult(nextIndex: elseInfo.afterBlock)
        }

        return LineResult(nextIndex: blockEnd.afterBlock)
    }

    // MARK: - Control Flow: For

    private func executeFor(lines: [String], index: Int) async throws -> LineResult {
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        guard line.hasSuffix("{") else {
            throw ProgramError("for block must end with '{'")
        }

        let forBody = String(line.dropFirst(4).dropLast(1)).trimmingCharacters(in: .whitespaces)
        guard let forMatch = forBody.firstMatch(of: /^\$([a-zA-Z_][a-zA-Z0-9_]*)\s+in\s+\$([a-zA-Z_][a-zA-Z0-9_]*)$/) else {
            throw ProgramError("for syntax: for $var in $collection {")
        }

        let iterVar = String(forMatch.1)
        let collectionVar = String(forMatch.2)

        guard let collection = variables[collectionVar] else {
            throw ProgramError("Undefined variable: $\(collectionVar)")
        }
        guard let elements = collection.elementListValue else {
            throw ProgramError("$\(collectionVar) is not iterable")
        }

        let bodyStart = index + 1
        let blockEnd = findBlockEnd(lines: lines, from: bodyStart)

        var iterations = 0
        let maxIterations = policy.maxLoopIterations

        for element in elements {
            guard iterations < maxIterations else {
                output.append("[warning] Loop iteration limit (\(maxIterations)) reached")
                break
            }
            guard ContinuousClock.now < deadline else {
                throw ProgramError("Program timed out during loop iteration")
            }

            variables[iterVar] = .element(element)
            var lineIdx = bodyStart

            while lineIdx < blockEnd.bodyEnd {
                let result = try await executeLine(lines: lines, index: lineIdx)
                lineIdx = result.nextIndex
            }

            iterations += 1
        }

        return LineResult(nextIndex: blockEnd.afterBlock)
    }

    // MARK: - Control Flow: Try/Catch

    private func executeTryCatch(lines: [String], index: Int) async throws -> LineResult {
        let bodyStart = index + 1
        let tryBlockEnd = findBlockEnd(lines: lines, from: bodyStart)

        var caughtError = false
        var lineIdx = bodyStart

        while lineIdx < tryBlockEnd.bodyEnd {
            do {
                let result = try await executeLine(lines: lines, index: lineIdx)
                lineIdx = result.nextIndex
            } catch let error as ProgramError {
                variables["_error"] = .string(error.message)
                caughtError = true
                break
            } catch {
                variables["_error"] = .string(error.localizedDescription)
                caughtError = true
                break
            }
        }

        if let catchBlock = tryBlockEnd.catchBlock {
            if caughtError {
                var catchIdx = catchBlock.bodyStart
                while catchIdx < catchBlock.bodyEnd {
                    let result = try await executeLine(lines: lines, index: catchIdx)
                    catchIdx = result.nextIndex
                }
            }
            return LineResult(nextIndex: catchBlock.afterBlock)
        }

        return LineResult(nextIndex: tryBlockEnd.afterBlock)
    }

    // MARK: - Block Parsing

    private struct BlockEnd {
        let bodyEnd: Int
        let afterBlock: Int
        let elseBlock: ElseBlock?
        let catchBlock: CatchBlock?
    }

    private struct ElseBlock {
        let bodyStart: Int
        let bodyEnd: Int
        let afterBlock: Int
    }

    private struct CatchBlock {
        let bodyStart: Int
        let bodyEnd: Int
        let afterBlock: Int
    }

    /// Finds the end of a `{ }` block starting at the given index (first line inside the block).
    /// Handles nested blocks.
    private func findBlockEnd(lines: [String], from startIndex: Int) -> BlockEnd {
        var depth = 1
        var i = startIndex

        while i < lines.count, depth > 0 {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.hasSuffix("{") {
                depth += 1
            } else if trimmed == "}" || trimmed.hasPrefix("} ") {
                depth -= 1
                if depth == 0 {
                    if trimmed.hasPrefix("} else {") || trimmed == "} else {" {
                        let elseBodyStart = i + 1
                        let elseEnd = findBlockEnd(lines: lines, from: elseBodyStart)
                        return BlockEnd(
                            bodyEnd: i,
                            afterBlock: elseEnd.afterBlock,
                            elseBlock: ElseBlock(
                                bodyStart: elseBodyStart,
                                bodyEnd: elseEnd.bodyEnd,
                                afterBlock: elseEnd.afterBlock,
                            ),
                            catchBlock: nil,
                        )
                    }
                    if trimmed.hasPrefix("} catch {") || trimmed == "} catch {" {
                        let catchBodyStart = i + 1
                        let catchEnd = findBlockEnd(lines: lines, from: catchBodyStart)
                        return BlockEnd(
                            bodyEnd: i,
                            afterBlock: catchEnd.afterBlock,
                            elseBlock: nil,
                            catchBlock: CatchBlock(
                                bodyStart: catchBodyStart,
                                bodyEnd: catchEnd.bodyEnd,
                                afterBlock: catchEnd.afterBlock,
                            ),
                        )
                    }
                    return BlockEnd(bodyEnd: i, afterBlock: i + 1, elseBlock: nil, catchBlock: nil)
                }
            }
            i += 1
        }

        // Unterminated block — treat rest of program as body
        return BlockEnd(bodyEnd: lines.count, afterBlock: lines.count, elseBlock: nil, catchBlock: nil)
    }

    // MARK: - Condition Evaluation

    private func evaluateCondition(_ condition: String) -> Bool {
        let trimmed = condition.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("not ") || trimmed.hasPrefix("!") {
            let inner = trimmed.hasPrefix("not ") ? String(trimmed.dropFirst(4)) : String(trimmed.dropFirst(1))
            return !evaluateCondition(inner.trimmingCharacters(in: .whitespaces))
        }

        if trimmed.hasPrefix("$") {
            let varName = stripDollar(trimmed)
            return variables[varName]?.boolValue ?? false
        }

        if let eqMatch = trimmed.firstMatch(of: /^\$([a-zA-Z_][a-zA-Z0-9_]*)\s*==\s*(.+)$/) {
            let varName = String(eqMatch.1)
            let rhs = String(eqMatch.2).trimmingCharacters(in: .whitespaces)
            let rhsValue = extractQuotedString(from: rhs) ?? rhs
            return (variables[varName]?.stringValue ?? "") == interpolate(rhsValue)
        }

        if let neqMatch = trimmed.firstMatch(of: /^\$([a-zA-Z_][a-zA-Z0-9_]*)\s*!=\s*(.+)$/) {
            let varName = String(neqMatch.1)
            let rhs = String(neqMatch.2).trimmingCharacters(in: .whitespaces)
            let rhsValue = extractQuotedString(from: rhs) ?? rhs
            return (variables[varName]?.stringValue ?? "") != interpolate(rhsValue)
        }

        if trimmed == "true" { return true }
        if trimmed == "false" { return false }

        return !trimmed.isEmpty
    }

    // MARK: - Predicate Parsing & Matching

    private enum Predicate {
        case role(String)
        case tag(String)
        case textContains(String)
        case textMatches(String)
        case ref(String)
    }

    /// Parses predicate tokens from the portion after `where`.
    private func parsePredicates(_ tokens: [String]) -> [Predicate] {
        var predicates: [Predicate] = []
        var i = 0

        while i < tokens.count {
            let token = tokens[i]

            if token.hasPrefix("role=") {
                predicates.append(.role(String(token.dropFirst(5))))
                i += 1
            } else if token.hasPrefix("tag=") {
                predicates.append(.tag(String(token.dropFirst(4))))
                i += 1
            } else if token.hasPrefix("ref=") {
                predicates.append(.ref(String(token.dropFirst(4))))
                i += 1
            } else if token == "text", i + 2 < tokens.count {
                let op = tokens[i + 1]
                if op == "contains" {
                    let value = extractQuotedString(from: tokens[(i + 2)...].joined(separator: " ")) ?? tokens[i + 2]
                    predicates.append(.textContains(interpolate(value)))
                    i = skipPastQuotedString(tokens: tokens, from: i + 2)
                } else if op == "matches" {
                    let value = extractQuotedString(from: tokens[(i + 2)...].joined(separator: " ")) ?? tokens[i + 2]
                    predicates.append(.textMatches(interpolate(value)))
                    i = skipPastQuotedString(tokens: tokens, from: i + 2)
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }

        return predicates
    }

    private func skipPastQuotedString(tokens: [String], from start: Int) -> Int {
        guard start < tokens.count else { return start + 1 }
        let token = tokens[start]
        if token.hasPrefix("\"") {
            if token.hasSuffix("\""), token.count > 1 {
                return start + 1
            }
            var i = start + 1
            while i < tokens.count {
                if tokens[i].hasSuffix("\"") {
                    return i + 1
                }
                i += 1
            }
            return i
        }
        return start + 1
    }

    /// Walks a content tree and returns all elements matching all predicates.
    private func queryElements(content: PageContentTree, predicates: [Predicate]) -> [ElementHandle] {
        var results: [ElementHandle] = []
        collectMatching(node: content.root, predicates: predicates, into: &results)
        return results
    }

    private func collectMatching(
        node: PageContentNode,
        predicates: [Predicate],
        into results: inout [ElementHandle],
    ) {
        if matchesAll(node: node, predicates: predicates) {
            if let handle = ElementHandle.from(node) {
                results.append(handle)
            }
        }
        for child in node.children {
            collectMatching(node: child, predicates: predicates, into: &results)
        }
    }

    private func matchesAll(node: PageContentNode, predicates: [Predicate]) -> Bool {
        for predicate in predicates {
            switch predicate {
            case let .role(role):
                let nodeRole = node.role ?? ""
                if nodeRole.lowercased() != role.lowercased() { return false }

            case let .tag(tag):
                if node.type.tagName.lowercased() != tag.lowercased() { return false }

            case let .textContains(text):
                let visibleText = collectVisibleText(from: node).lowercased()
                if !visibleText.contains(text.lowercased()) { return false }

            case let .textMatches(pattern):
                let visibleText = collectVisibleText(from: node)
                guard let regex = try? Regex(pattern) else { return false }
                if visibleText.firstMatch(of: regex) == nil { return false }

            case let .ref(ref):
                if node.ref != ref { return false }
            }
        }
        return true
    }

    /// Builds a server-side FindElementsParams from parsed predicates.
    private func buildFindElementsParams(from predicates: [Predicate]) -> ControlRequest.FindElementsParams {
        var text: String?
        var role: String?
        var tag: String?

        for predicate in predicates {
            switch predicate {
            case let .role(r): role = r
            case let .tag(t): tag = t
            case let .textContains(t): text = t
            case let .textMatches(t): text = t
            case let .ref(r): text = r
            }
        }

        return ControlRequest.FindElementsParams(text: text, role: role, tag: tag, limit: 100, tabID: tabID, pageID: pageID)
    }

    // MARK: - Response Mapping

    /// Routes a request through the control server and maps the response to a ProgramValue.
    @discardableResult
    private func executeRoute(_ request: ControlRequest) async throws -> ProgramValue {
        let response = await controlServer.route(request)
        return try mapResponse(response)
    }

    private func mapResponse(_ response: ControlResponse) throws -> ProgramValue {
        switch response {
        case let .ok(message):
            return .string(message ?? "ok")
        case let .pageContent(text):
            return .string(text)
        case let .screenshot(info):
            return .string("Screenshot captured (\(info.width)x\(info.height))")
        case let .error(info):
            throw ProgramError("\(info.code): \(info.message)")
        case let .actionResult(info):
            if !info.success {
                throw ProgramError(info.message ?? "Action failed")
            }
            return .string(info.message ?? "ok")
        case let .foundElements(elements):
            let handles = elements.map { elementInfoToHandle($0) }
            return .elementList(handles)
        case let .javascript(result):
            return .string(result)
        case let .execResult(info):
            if !info.success {
                throw ProgramError(info.error ?? "Execution failed")
            }
            return .string(info.output.joined(separator: "\n"))
        default:
            return .string("ok")
        }
    }

    /// Resolves a bare ref string to an ``ElementHandle`` by querying the server.
    private func resolveRefToElement(_ ref: String) async -> ElementHandle? {
        let params = ControlRequest.FindElementsParams(text: nil, role: nil, tag: nil, limit: 500, tabID: tabID, pageID: pageID)
        let response = await controlServer.route(.findElements(params))
        if case let .foundElements(elements) = response {
            if let match = elements.first(where: { $0.ref == ref }) {
                return elementInfoToHandle(match)
            }
        }
        return nil
    }

    private func elementInfoToHandle(_ info: CTL.FoundElementInfo) -> ElementHandle {
        ElementHandle(
            ref: info.ref,
            text: info.text,
            tag: info.tag,
            role: info.role,
            href: info.href,
            value: nil,
            inputType: info.inputType,
            rect: info.rect,
        )
    }

    // MARK: - Visual Feedback

    private enum FeedbackAction {
        case clicking
        case hovering
    }

    @discardableResult
    private func withVisualFeedback(
        element: ElementHandle?,
        action: FeedbackAction,
        perform: () async -> ControlResponse,
    ) async throws -> ProgramValue {
        if let element, let rect = element.rect {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            visualFeedback.moveCursor(to: center, in: rect)
            visualFeedback.highlightElement(rect: rect, style: .aboutToAct)
            let delay = visualFeedback.speed.duration
            try? await Task.sleep(for: .seconds(delay))
        }

        let response = await perform()

        if element?.rect != nil {
            switch action {
            case .clicking:
                visualFeedback.setCursorState(.clicking)
                try? await Task.sleep(for: .milliseconds(150))
            case .hovering:
                visualFeedback.setCursorState(.hovering)
                try? await Task.sleep(for: .milliseconds(100))
            }
            visualFeedback.setCursorState(.idle)
            visualFeedback.clearHighlights()
        }

        return try mapResponse(response)
    }

    // MARK: - String Interpolation

    /// Replaces `${var}` and `${var.property}` with their values.
    private func interpolate(_ string: String) -> String {
        let pattern = /\$\{([a-zA-Z_][a-zA-Z0-9_]*)(?:\.([a-zA-Z_]+))?\}/
        var result = string

        while let match = result.firstMatch(of: pattern) {
            let varName = String(match.1)
            let propName = match.2.map { String($0) }

            let replacement: String = if varName == "page" {
                variables["_page_\(propName ?? "")"]?.stringValue ?? ""
            } else if let value = variables[varName], let prop = propName, case let .element(el) = value {
                el.property(prop) ?? ""
            } else {
                variables[varName]?.stringValue ?? ""
            }

            result = result.replacingCharacters(in: match.range, with: replacement)
        }

        return result
    }

    // MARK: - Text Helpers

    /// Collects visible text content from a node recursively.
    private func collectVisibleText(from node: PageContentNode) -> String {
        var parts: [String] = []
        collectTextRecursive(node, into: &parts, depth: 0)
        return parts.joined(separator: " ")
    }

    private func collectTextRecursive(_ node: PageContentNode, into parts: inout [String], depth: Int) {
        guard depth < 6 else { return }

        if case let .text(content) = node.type {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
            return
        }

        if let name = node.name, !name.isEmpty {
            parts.append(name)
        }

        for child in node.children {
            collectTextRecursive(child, into: &parts, depth: depth + 1)
        }
    }

    // MARK: - Tokenization

    /// Splits a command line into tokens, respecting quoted strings.
    private func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        var escapeNext = false

        for char in line {
            if escapeNext {
                current.append(char)
                escapeNext = false
                continue
            }
            if char == "\\" {
                escapeNext = true
                continue
            }
            if char == "\"" {
                if inQuote {
                    current.append(char)
                    tokens.append(current)
                    current = ""
                    inQuote = false
                } else {
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                    current.append(char)
                    inQuote = true
                }
                continue
            }
            if char == " ", !inQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(char)
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    /// Extracts content between quotes from a string, returning nil if no quotes found.
    private func extractQuotedString(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\"") else { return nil }

        // Find closing quote (handling escaped quotes)
        var i = trimmed.index(after: trimmed.startIndex)
        var result = ""
        var escapeNext = false

        while i < trimmed.endIndex {
            let char = trimmed[i]
            if escapeNext {
                result.append(char)
                escapeNext = false
            } else if char == "\\" {
                escapeNext = true
            } else if char == "\"" {
                return result
            } else {
                result.append(char)
            }
            i = trimmed.index(after: i)
        }

        // No closing quote found — return everything after the opening quote
        return result
    }

    /// Strips the leading `$` from a variable reference.
    private func stripDollar(_ s: String) -> String {
        s.hasPrefix("$") ? String(s.dropFirst()) : s
    }

    /// Resolves a token (e.g. `$var` or bare ref like `e5`) to an element ref string.
    /// If the variable holds an `.element`, returns the element's ref.
    /// Otherwise returns the variable's string value or the interpolated token.
    private func resolveRef(_ token: String) throws -> String {
        guard token.hasPrefix("$") else { return interpolate(token) }
        let varName = stripDollar(token)
        guard let value = variables[varName] else {
            throw ProgramError("Undefined variable: $\(varName)")
        }
        if case let .element(el) = value { return el.ref }
        return value.stringValue
    }

    /// Resolves a token to its `ProgramValue`, or returns an interpolated string value for bare tokens.
    private func resolveValue(_ token: String) throws -> ProgramValue {
        guard token.hasPrefix("$") else { return .string(interpolate(token)) }
        let varName = stripDollar(token)
        guard let value = variables[varName] else {
            throw ProgramError("Undefined variable: $\(varName)")
        }
        return value
    }

    /// Extracts an integer value for a flag like `--timeout 30`.
    private func extractIntFlag(parts: [String], flag: String) -> Int? {
        guard let idx = parts.firstIndex(of: flag), idx + 1 < parts.count else { return nil }
        return Int(parts[idx + 1])
    }

    /// Counts lines that would execute (non-blank, non-comment, not block delimiters).
    private func countExecutableLines(_ lines: [String]) -> Int {
        var count = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "}" || trimmed == "} else {" || trimmed == "} catch {" {
                continue
            }
            count += 1
        }
        return count
    }

    // MARK: - Security Policy Enforcement

    private func checkNavigationLimit() throws {
        navigationCount += 1
        guard navigationCount <= policy.maxNavigations else {
            throw ProgramError("Security policy: navigation limit exceeded (\(policy.maxNavigations))")
        }
    }

    private func checkInteractionLimit() throws {
        interactionCount += 1
        guard interactionCount <= policy.maxInteractions else {
            throw ProgramError("Security policy: interaction limit exceeded (\(policy.maxInteractions))")
        }
    }

    /// Checks the interaction limit, executes the command, then invalidates the page content
    /// cache since the command may have mutated the DOM.
    private func executeMutatingInteraction(_ body: () async throws -> ProgramValue) async throws -> ProgramValue {
        try checkInteractionLimit()
        let result = try await body()
        PageContentExtractor.clearAllCaches()
        return result
    }

    private func checkPageReadLimit() throws {
        pageReadCount += 1
        guard pageReadCount <= policy.maxPageReads else {
            throw ProgramError("Security policy: page read limit exceeded (\(policy.maxPageReads))")
        }
    }

    /// Checks a URL string against the policy's domain allow/block lists.
    private func checkDomainPolicy(urlString: String) throws {
        guard let url = URL(string: urlString), let host = url.host else { return }

        if let blockedDomains = policy.blockedDomains {
            if blockedDomains.contains(where: { host.hasSuffix($0) }) {
                throw ProgramError("Security policy: domain '\(host)' is blocked")
            }
        }

        if let allowedDomains = policy.allowedDomains {
            if !allowedDomains.contains(where: { host.hasSuffix($0) }) {
                throw ProgramError("Security policy: domain '\(host)' is not in the allowed list")
            }
        }
    }

    /// Checks the current page URL against domain policy after navigation,
    /// catching redirects to forbidden domains. Navigates back if violated.
    private func checkCurrentURLAgainstPolicy() async throws {
        guard policy.allowedDomains != nil || policy.blockedDomains != nil else { return }

        let response = await controlServer.route(.tabURL(ControlRequest.OptionalTabIDParams(tabID: tabID, pageID: pageID)))
        if case let .ok(urlString) = response, let urlString, !urlString.isEmpty {
            do {
                try checkDomainPolicy(urlString: urlString)
            } catch {
                _ = await controlServer.route(.tabGoBack(ControlRequest.OptionalTabIDParams(tabID: tabID, pageID: pageID)))
                throw error
            }
        }
    }

    /// Checks if a form field is sensitive and enforces the policy.
    private func checkSensitiveField(_ element: ElementHandle) throws {
        guard SensitiveFieldDetector.isSensitive(element) else { return }

        switch policy.sensitiveFieldPolicy {
        case .block:
            throw ProgramError("Security policy: filling sensitive field '\(element.ref)' is blocked")
        case .requireConfirmation:
            output.append("[CONFIRM_REQUIRED] Sensitive field '\(element.ref)' requires user confirmation")
            throw ProgramError("Security policy: sensitive field '\(element.ref)' requires confirmation before filling")
        case .allow:
            break
        }
    }

    // MARK: - Error Type

    private struct ProgramError: Error {
        let message: String
        init(_ message: String) {
            self.message = message
        }
    }
}
