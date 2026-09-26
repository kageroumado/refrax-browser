import Foundation
import os

/// A locally installed coding-agent CLI that Refrax drives as its reasoning runtime.
///
/// Each runtime signs in with the user's own account, so Refrax needs no API key.
/// The agent acts on the browser through `refrax-ctl`.
nonisolated enum CLIAgentRuntime: String, CaseIterable, Sendable {
    /// Claude Code: `claude -p --output-format stream-json`.
    case claudeCode

    /// Codex: `codex exec --json`.
    case codex

    /// The executable name looked up on disk.
    var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        }
    }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// One line telling the user how to make this runtime available.
    var installHint: String {
        switch self {
        case .claudeCode: "Install Claude Code (claude.com/claude-code) and sign in, or pick another provider."
        case .codex: "Install Codex (brew install codex) and sign in, or pick another provider."
        }
    }

    /// Builds the argument list for one turn.
    ///
    /// The prompt itself goes through standard input, which keeps it out of
    /// `ps` output and away from variadic option parsing.
    ///
    /// - Parameters:
    ///   - sessionID: The CLI session to continue, or `nil` for the first turn.
    ///   - model: The model slug, or an empty string for the CLI's default.
    ///   - systemPrompt: Instructions appended to the CLI's own system prompt.
    ///   - refraxCtlPath: Absolute path of the `refrax-ctl` helper the agent may run.
    ///   - imagePaths: Image attachments written to disk for this turn.
    func arguments(
        sessionID: String?,
        model: String,
        systemPrompt: String,
        refraxCtlPath: String?,
        imagePaths: [String],
    ) -> [String] {
        switch self {
        case .claudeCode:
            claudeCodeArguments(
                sessionID: sessionID,
                model: model,
                systemPrompt: systemPrompt,
                refraxCtlPath: refraxCtlPath,
            )
        case .codex:
            codexArguments(
                sessionID: sessionID,
                model: model,
                systemPrompt: systemPrompt,
                imagePaths: imagePaths,
            )
        }
    }

    /// Claude Code runs with only Bash, Read, WebFetch, WebSearch and Skill
    /// available, and `dontAsk` denies every call no rule pre-approves: Bash
    /// is approved for `refrax-ctl` alone and Read for the session directory.
    /// `--strict-mcp-config` keeps the user's MCP servers out of the context.
    private func claudeCodeArguments(
        sessionID: String?,
        model: String,
        systemPrompt: String,
        refraxCtlPath: String?,
    ) -> [String] {
        var allowed = ["Bash(refrax-ctl:*)", "Read(./**)", "WebFetch", "WebSearch", "Skill"]
        if let refraxCtlPath {
            allowed.append("Bash(\(refraxCtlPath):*)")
        }

        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", "dontAsk",
            "--strict-mcp-config",
            "--tools", "Bash,Read,WebFetch,WebSearch,Skill",
            "--append-system-prompt", systemPrompt,
        ]
        if let sessionID {
            arguments += ["--resume", sessionID]
        }
        if !model.isEmpty {
            arguments += ["--model", model]
        }
        arguments.append("--allowedTools")
        arguments += allowed
        return arguments
    }

    /// Codex runs with approvals off and the sandbox open: its macOS sandbox
    /// blocks the Unix socket `refrax-ctl` talks to, and `exec` offers no
    /// per-command allowlist.
    private func codexArguments(
        sessionID: String?,
        model: String,
        systemPrompt: String,
        imagePaths: [String],
    ) -> [String] {
        var arguments = ["exec"]
        if sessionID != nil {
            arguments.append("resume")
        }
        // `-i` is variadic on `exec`, so images come before the flags that end it.
        for path in imagePaths {
            arguments += ["-i", path]
        }
        arguments += [
            "--json",
            "--skip-git-repo-check",
            "-c", #"sandbox_mode="danger-full-access""#,
            "-c", #"approval_policy="never""#,
            "-c", "developer_instructions=\(Self.tomlString(systemPrompt))",
        ]
        if !model.isEmpty {
            arguments += ["-m", model]
        }
        if let sessionID {
            arguments.append(sessionID)
        }
        arguments.append("-")
        return arguments
    }

    /// Encodes a string as a TOML basic string for `codex -c key=value`.
    static func tomlString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    escaped += String(format: "\\u%04X", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return "\"\(escaped)\""
    }
}

// MARK: - Locating Binaries

/// Finds CLI binaries without relying on the GUI app's minimal `PATH`.
///
/// Probes the usual install locations first, then asks a login shell once
/// per runtime and caches the answer for the rest of the session.
nonisolated enum CLIAgentLocator {
    private static let cache = OSAllocatedUnfairLock<[CLIAgentRuntime: String]>(initialState: [:])

    /// Seconds to wait for the login shell before giving up.
    private static let loginShellTimeout: Duration = .seconds(5)

    /// The account's home directory from the user database. `NSHomeDirectory()` follows
    /// `CFFIXED_USER_HOME`, which can point somewhere the CLIs were never installed.
    static let userHomeDirectory: String = {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return NSHomeDirectory()
        }
        return String(cString: directory)
    }()

    /// Install locations probed in order.
    static func candidatePaths(for runtime: CLIAgentRuntime, home: String = userHomeDirectory) -> [String] {
        var directories = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
        ]
        if runtime == .claudeCode {
            directories.insert("\(home)/.claude/local", at: 1)
        }
        return directories.map { "\($0)/\(runtime.executableName)" }
    }

    /// The cached or probed location, using only file-system checks.
    ///
    /// Cheap enough to call from a view body.
    static func installedURL(for runtime: CLIAgentRuntime) -> URL? {
        if let cached = cache.withLock({ $0[runtime] }) {
            return URL(fileURLWithPath: cached)
        }
        let fileManager = FileManager.default
        guard let path = candidatePaths(for: runtime).first(where: fileManager.isExecutableFile(atPath:)) else {
            return nil
        }
        cache.withLock { $0[runtime] = path }
        return URL(fileURLWithPath: path)
    }

    /// The binary's location, falling back to `command -v` in a login shell.
    static func locate(_ runtime: CLIAgentRuntime) async -> URL? {
        if let url = installedURL(for: runtime) {
            return url
        }
        guard let path = await loginShellLookup(runtime.executableName),
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        cache.withLock { $0[runtime] = path }
        return URL(fileURLWithPath: path)
    }

    /// Absolute path of the `refrax-ctl` helper the agent should run: the copy
    /// bundled with this build, which always speaks its protocol, else the
    /// installed one.
    static var refraxCtlPath: String? {
        let bundled = (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Helpers/refrax-ctl")
        let fileManager = FileManager.default
        if fileManager.isExecutableFile(atPath: bundled) {
            return bundled
        }
        if fileManager.isExecutableFile(atPath: RefraxControlHost.cliHelperDestination) {
            return RefraxControlHost.cliHelperDestination
        }
        return nil
    }

    private static func loginShellLookup(_ name: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(name)"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        let (exits, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let pid = process.processIdentifier
        let timeout = Task(name: "CLI lookup timeout") {
            try? await Task.sleep(for: loginShellTimeout)
            guard !Task.isCancelled else { return }
            kill(pid, SIGKILL)
        }
        var status: Int32 = -1
        for await code in exits {
            status = code
        }
        timeout.cancel()

        guard status == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let path, path.hasPrefix("/") else { return nil }
        return path
    }

    /// Builds the child environment: the app's own, with the binary's
    /// directory and the common tool directories on `PATH`.
    ///
    /// Drops the variables Claude Code sets for its own children, so a Refrax
    /// launched from a Claude Code terminal still starts a top-level session.
    static func environment(binary: URL, refraxCtlPath: String?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CLAUDECODE")
        environment.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")

        var directories = [binary.deletingLastPathComponent().path]
        if let refraxCtlPath {
            directories.append((refraxCtlPath as NSString).deletingLastPathComponent)
        }
        directories += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        if let existing = environment["PATH"] {
            directories += existing.split(separator: ":").map(String.init)
        }
        var seen = Set<String>()
        environment["PATH"] = directories.filter { seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }
}

// MARK: - Child Process Registry

/// Tracks running CLI agent processes so app termination can stop them.
///
/// Children of a quitting app are reparented to launchd and keep running,
/// so ``terminateAll()`` runs from `applicationWillTerminate`.
nonisolated enum CLIProcessRegistry {
    private static let running = OSAllocatedUnfairLock<Set<pid_t>>(initialState: [])

    static func register(_ pid: pid_t) {
        running.withLock { _ = $0.insert(pid) }
    }

    static func unregister(_ pid: pid_t) {
        running.withLock { _ = $0.remove(pid) }
    }

    static func isRunning(_ pid: pid_t) -> Bool {
        running.withLock { $0.contains(pid) }
    }

    /// Sends SIGTERM to every registered process.
    static func terminateAll() {
        let pids = running.withLock { pids in
            defer { pids.removeAll() }
            return pids
        }
        for pid in pids {
            kill(pid, SIGTERM)
        }
    }
}
