import Foundation
import OSLog

/// Installs the `refrax-ctl` Claude Code skill to the user's skill directory.
///
/// The skill teaches AI agents how to control Refrax via the CLI. Skill files
/// are bundled as resources and copied to `~/.claude/skills/refrax-ctl/` at runtime.
///
/// Only installs when Claude Code is detected (`~/.claude/` exists).
/// Thread-safe: uses only Foundation file APIs.
nonisolated enum CLISkillInstaller {
    private static let logger = OSLog(subsystem: "website.refrax.browser", category: "cli-skill")

    private static let skillName = "refrax-ctl"

    /// Maps bundle resource names to destination paths relative to the skill directory.
    static let fileMapping: [(resource: String, destination: String)] = [
        ("refrax-ctl-skill", "SKILL.md"),
        ("refrax-ctl-dsl", "references/dsl.md"),
        ("refrax-ctl-commands", "references/commands.md"),
        ("refrax-ctl-security", "references/security.md"),
    ]

    /// The target directory for the installed skill.
    private static var skillDirectory: String {
        "\(NSHomeDirectory())/.claude/skills/\(skillName)"
    }

    /// Whether the skill is currently installed.
    static var isInstalled: Bool {
        isInstalled(skillDir: skillDirectory)
    }

    /// Whether the skill SKILL.md exists at the given directory.
    static func isInstalled(skillDir: String) -> Bool {
        let skillFile = (skillDir as NSString).appendingPathComponent("SKILL.md")
        return FileManager.default.fileExists(atPath: skillFile)
    }

    /// Installs skill files from the app bundle to the user's Claude Code skills directory.
    ///
    /// Creates the directory structure and copies all skill files. Overwrites existing
    /// files to keep them current after app updates. Skips silently if Claude Code
    /// is not installed or bundle resources are missing.
    static func install() {
        let claudeDir = "\(NSHomeDirectory())/.claude"

        var files: [(source: URL, destination: String)] = []
        for (resource, destination) in fileMapping {
            guard let url = Bundle.main.url(
                forResource: resource,
                withExtension: "md"
            ) else {
                os_log("Skill resource not found in bundle: %{public}@", log: logger, type: .error, resource)
                continue
            }
            files.append((url, destination))
        }

        install(claudeDir: claudeDir, skillDir: skillDirectory, files: files)
    }

    /// Core installation logic with injectable paths for testing.
    ///
    /// - Parameters:
    ///   - claudeDir: Path to check for Claude Code presence. Pass `nil` to skip the check.
    ///   - skillDir: Target directory for the installed skill.
    ///   - files: Source URLs mapped to destination paths relative to `skillDir`.
    /// - Returns: Number of files successfully installed.
    @discardableResult
    static func install(
        claudeDir: String?,
        skillDir: String,
        files: [(source: URL, destination: String)]
    ) -> Int {
        let fm = FileManager.default

        // Only install if Claude Code is present (skip check if claudeDir is nil)
        if let claudeDir, !fm.fileExists(atPath: claudeDir) {
            os_log("Claude Code not detected, skipping skill install", log: logger, type: .info)
            return 0
        }

        let referencesDir = (skillDir as NSString).appendingPathComponent("references")
        do {
            try fm.createDirectory(atPath: referencesDir, withIntermediateDirectories: true)
        } catch {
            os_log(
                "Failed to create skill directory: %{public}@",
                log: logger, type: .error, error.localizedDescription,
            )
            return 0
        }

        var installedCount = 0
        for (sourceURL, destination) in files {
            let destPath = (skillDir as NSString).appendingPathComponent(destination)

            do {
                let content = try String(contentsOf: sourceURL, encoding: .utf8)
                try content.write(toFile: destPath, atomically: true, encoding: .utf8)
                installedCount += 1
            } catch {
                os_log(
                    "Failed to install skill file %{public}@: %{public}@",
                    log: logger, type: .error, destination, error.localizedDescription,
                )
            }
        }

        if installedCount > 0 {
            os_log(
                "CLI skill installed (%d files) to %{public}@",
                log: logger, type: .info, installedCount, skillDir,
            )
        }
        return installedCount
    }

    /// Removes the installed skill directory.
    static func uninstall() {
        uninstall(skillDir: skillDirectory)
    }

    /// Removes the skill at the given directory.
    static func uninstall(skillDir: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillDir) else { return }

        do {
            try fm.removeItem(atPath: skillDir)
            os_log("CLI skill uninstalled from %{public}@", log: logger, type: .info, skillDir)
        } catch {
            os_log(
                "Failed to uninstall skill: %{public}@",
                log: logger, type: .error, error.localizedDescription,
            )
        }
    }
}
