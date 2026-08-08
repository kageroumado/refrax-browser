import Foundation
import SwiftData
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for CLI helper installation and skill installer.
    @Tag static var cliInstaller: Self
}

// MARK: - Temp Directory Helper

/// Creates a unique temporary directory for test isolation. Automatically cleaned up by the caller.
private func makeTempDir() throws -> String {
    let dir = NSTemporaryDirectory() + "refrax-test-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

/// Creates test source markdown files matching the skill file mapping.
private func createSourceFiles(in dir: String) throws -> [(source: URL, destination: String)] {
    let fm = FileManager.default
    try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

    var files: [(source: URL, destination: String)] = []
    for (resource, destination) in CLISkillInstaller.fileMapping {
        let filePath = (dir as NSString).appendingPathComponent("\(resource).md")
        try "# Test content for \(resource)".write(toFile: filePath, atomically: true, encoding: .utf8)
        files.append((URL(fileURLWithPath: filePath), destination))
    }
    return files
}

/// Creates a binary file of the given size filled with a repeating byte.
private func createBinary(at path: String, size: Int, byte: UInt8 = 0xAA) throws {
    let data = Data(repeating: byte, count: size)
    try data.write(to: URL(fileURLWithPath: path))
}

// MARK: - CLISkillInstaller Install Tests

@Suite("CLISkillInstaller Install", .tags(.cliInstaller))
struct CLISkillInstallerInstallTests {
    @Test("Installs all skill files to correct directory structure")
    func installCreatesCorrectStructure() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let sourceDir = (tempDir as NSString).appendingPathComponent("sources")
        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")
        let claudeDir = (tempDir as NSString).appendingPathComponent("claude")
        try FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)

        let files = try createSourceFiles(in: sourceDir)

        let count = CLISkillInstaller.install(claudeDir: claudeDir, skillDir: skillDir, files: files)

        #expect(count == 4)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: (skillDir as NSString).appendingPathComponent("SKILL.md")))
        #expect(fm.fileExists(atPath: (skillDir as NSString).appendingPathComponent("references/dsl.md")))
        #expect(fm.fileExists(atPath: (skillDir as NSString).appendingPathComponent("references/commands.md")))
        #expect(fm.fileExists(atPath: (skillDir as NSString).appendingPathComponent("references/security.md")))
    }

    @Test("Preserves source file content in destination")
    func preservesContent() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let sourceDir = (tempDir as NSString).appendingPathComponent("sources")
        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")

        let files = try createSourceFiles(in: sourceDir)
        CLISkillInstaller.install(claudeDir: nil, skillDir: skillDir, files: files)

        let destPath = (skillDir as NSString).appendingPathComponent("SKILL.md")
        let content = try String(contentsOfFile: destPath, encoding: .utf8)
        #expect(content == "# Test content for refrax-ctl-skill")
    }

    @Test("Skips install when Claude Code directory doesn't exist")
    func skipWhenNoClaudeDir() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let sourceDir = (tempDir as NSString).appendingPathComponent("sources")
        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")
        let nonexistentClaudeDir = (tempDir as NSString).appendingPathComponent("no-claude")

        let files = try createSourceFiles(in: sourceDir)
        let count = CLISkillInstaller.install(claudeDir: nonexistentClaudeDir, skillDir: skillDir, files: files)

        #expect(count == 0)
        #expect(!FileManager.default.fileExists(atPath: skillDir))
    }

    @Test("Installs without Claude dir check when nil")
    func installWithNilClaudeDir() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let sourceDir = (tempDir as NSString).appendingPathComponent("sources")
        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")

        let files = try createSourceFiles(in: sourceDir)
        let count = CLISkillInstaller.install(claudeDir: nil, skillDir: skillDir, files: files)

        #expect(count == 4)
    }

    @Test("Overwrites existing files on re-install")
    func overwritesOnReinstall() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let sourceDir = (tempDir as NSString).appendingPathComponent("sources")
        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")

        let files = try createSourceFiles(in: sourceDir)
        CLISkillInstaller.install(claudeDir: nil, skillDir: skillDir, files: files)

        // Modify source and re-install
        let updatedContent = "# Updated content"
        try updatedContent.write(to: files[0].source, atomically: true, encoding: .utf8)

        let count = CLISkillInstaller.install(claudeDir: nil, skillDir: skillDir, files: files)
        #expect(count == 4)

        let destPath = (skillDir as NSString).appendingPathComponent(files[0].destination)
        let content = try String(contentsOfFile: destPath, encoding: .utf8)
        #expect(content == updatedContent)
    }

    @Test("Empty file list returns zero")
    func emptyFileList() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")
        let count = CLISkillInstaller.install(claudeDir: nil, skillDir: skillDir, files: [])

        #expect(count == 0)
    }

    @Test("Creates references subdirectory even with no reference files")
    func createsReferencesSubdir() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")
        CLISkillInstaller.install(claudeDir: nil, skillDir: skillDir, files: [])

        let referencesDir = (skillDir as NSString).appendingPathComponent("references")
        #expect(FileManager.default.fileExists(atPath: referencesDir))
    }
}

// MARK: - CLISkillInstaller File Mapping Tests

@Suite("CLISkillInstaller File Mapping", .tags(.cliInstaller))
struct CLISkillInstallerFileMappingTests {
    @Test("File mapping contains expected entries")
    func fileMappingIsCorrect() {
        let mapping = CLISkillInstaller.fileMapping
        #expect(mapping.count == 4)

        let destinations = mapping.map(\.destination)
        #expect(destinations.contains("SKILL.md"))
        #expect(destinations.contains("references/dsl.md"))
        #expect(destinations.contains("references/commands.md"))
        #expect(destinations.contains("references/security.md"))
    }

    @Test("All resource names use consistent prefix")
    func resourceNamesConsistent() {
        for (resource, _) in CLISkillInstaller.fileMapping {
            #expect(resource.hasPrefix("refrax-ctl-"))
        }
    }
}

// MARK: - CLISkillInstaller Uninstall Tests

@Suite("CLISkillInstaller Uninstall", .tags(.cliInstaller))
struct CLISkillInstallerUninstallTests {
    @Test("Uninstall removes the skill directory and all contents")
    func uninstallRemovesDirectory() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")
        let fm = FileManager.default

        // Create a skill directory with files
        let refsDir = (skillDir as NSString).appendingPathComponent("references")
        try fm.createDirectory(atPath: refsDir, withIntermediateDirectories: true)
        try "test".write(toFile: (skillDir as NSString).appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "test".write(toFile: (refsDir as NSString).appendingPathComponent("commands.md"), atomically: true, encoding: .utf8)
        #expect(fm.fileExists(atPath: skillDir))

        CLISkillInstaller.uninstall(skillDir: skillDir)

        #expect(!fm.fileExists(atPath: skillDir))
    }

    @Test("Uninstall is no-op when directory doesn't exist")
    func uninstallNoOpWhenMissing() {
        let nonexistent = NSTemporaryDirectory() + "refrax-nonexistent-\(UUID().uuidString)"
        // Should not throw or crash
        CLISkillInstaller.uninstall(skillDir: nonexistent)
    }
}

// MARK: - CLISkillInstaller isInstalled Tests

@Suite("CLISkillInstaller isInstalled", .tags(.cliInstaller))
struct CLISkillInstallerIsInstalledTests {
    @Test("Returns true when SKILL.md exists")
    func installedWhenFileExists() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        try "test".write(
            toFile: (tempDir as NSString).appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8,
        )

        #expect(CLISkillInstaller.isInstalled(skillDir: tempDir))
    }

    @Test("Returns false when SKILL.md is missing")
    func notInstalledWhenMissing() {
        let nonexistent = NSTemporaryDirectory() + "refrax-nonexistent-\(UUID().uuidString)"
        #expect(!CLISkillInstaller.isInstalled(skillDir: nonexistent))
    }

    @Test("Returns false when directory exists but SKILL.md is missing")
    func notInstalledWhenDirExistsButNoFile() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Directory exists but no SKILL.md inside
        #expect(!CLISkillInstaller.isInstalled(skillDir: tempDir))
    }
}

// MARK: - CLISkillInstaller Install + Uninstall Round-Trip

@Suite("CLISkillInstaller Round-Trip", .tags(.cliInstaller))
struct CLISkillInstallerRoundTripTests {
    @Test("Install then uninstall leaves no artifacts")
    func roundTrip() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let sourceDir = (tempDir as NSString).appendingPathComponent("sources")
        let skillDir = (tempDir as NSString).appendingPathComponent("skills/refrax-ctl")

        let files = try createSourceFiles(in: sourceDir)

        CLISkillInstaller.install(claudeDir: nil, skillDir: skillDir, files: files)
        #expect(CLISkillInstaller.isInstalled(skillDir: skillDir))

        CLISkillInstaller.uninstall(skillDir: skillDir)
        #expect(!CLISkillInstaller.isInstalled(skillDir: skillDir))
        #expect(!FileManager.default.fileExists(atPath: skillDir))
    }
}

// MARK: - RefraxControlHost copyBinary Tests

@Suite("RefraxControlHost copyBinary", .tags(.cliInstaller))
struct CopyBinaryTests {
    @Test("Copies binary to destination")
    func copiesBinary() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let source = (tempDir as NSString).appendingPathComponent("source-binary")
        let dest = (tempDir as NSString).appendingPathComponent("dest-binary")
        try createBinary(at: source, size: 1024)

        RefraxControlHost.copyBinary(from: source, to: dest)

        #expect(FileManager.default.fileExists(atPath: dest))
        let destData = try Data(contentsOf: URL(fileURLWithPath: dest))
        #expect(destData.count == 1024)
    }

    @Test("Copied binary preserves content")
    func preservesContent() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let source = (tempDir as NSString).appendingPathComponent("source-binary")
        let dest = (tempDir as NSString).appendingPathComponent("dest-binary")
        try createBinary(at: source, size: 256, byte: 0x42)

        RefraxControlHost.copyBinary(from: source, to: dest)

        let destData = try Data(contentsOf: URL(fileURLWithPath: dest))
        #expect(destData.allSatisfy { $0 == 0x42 })
    }

    @Test("Skips copy when destination content is identical")
    func skipsWhenContentIdentical() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let source = (tempDir as NSString).appendingPathComponent("source-binary")
        let dest = (tempDir as NSString).appendingPathComponent("dest-binary")

        try createBinary(at: source, size: 512, byte: 0xAA)
        try createBinary(at: dest, size: 512, byte: 0xAA)

        let attrsBefore = try FileManager.default.attributesOfItem(atPath: dest)

        RefraxControlHost.copyBinary(from: source, to: dest)

        // File was left in place, not replaced with a fresh copy
        let attrsAfter = try FileManager.default.attributesOfItem(atPath: dest)
        #expect(attrsBefore[.creationDate] as? Date == attrsAfter[.creationDate] as? Date)
    }

    @Test("Overwrites when destination has same size but different content")
    func overwritesWhenSameSizeDifferentContent() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let source = (tempDir as NSString).appendingPathComponent("source-binary")
        let dest = (tempDir as NSString).appendingPathComponent("dest-binary")

        // Rebuilt helpers can coincide in length while differing in content
        try createBinary(at: source, size: 512, byte: 0xAA)
        try createBinary(at: dest, size: 512, byte: 0xBB)

        RefraxControlHost.copyBinary(from: source, to: dest)

        let destData = try Data(contentsOf: URL(fileURLWithPath: dest))
        #expect(destData[0] == 0xAA)
    }

    @Test("Overwrites when destination has different size")
    func overwritesWhenDifferentSize() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let source = (tempDir as NSString).appendingPathComponent("source-binary")
        let dest = (tempDir as NSString).appendingPathComponent("dest-binary")

        try createBinary(at: source, size: 1024)
        try createBinary(at: dest, size: 512)

        RefraxControlHost.copyBinary(from: source, to: dest)

        let destData = try Data(contentsOf: URL(fileURLWithPath: dest))
        #expect(destData.count == 1024)
    }

    @Test("Creates intermediate directory when specified")
    func createsDirectory() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let source = (tempDir as NSString).appendingPathComponent("source-binary")
        let destDir = (tempDir as NSString).appendingPathComponent("nested/dir")
        let dest = (destDir as NSString).appendingPathComponent("binary")

        try createBinary(at: source, size: 256)

        RefraxControlHost.copyBinary(from: source, to: dest, createDirectory: destDir)

        #expect(FileManager.default.fileExists(atPath: dest))
    }

    @Test("Does not create directory when not specified")
    func doesNotCreateDirectoryByDefault() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let source = (tempDir as NSString).appendingPathComponent("source-binary")
        let dest = (tempDir as NSString).appendingPathComponent("missing-dir/binary")

        try createBinary(at: source, size: 256)

        // Should fail silently — directory doesn't exist and we didn't ask to create it
        RefraxControlHost.copyBinary(from: source, to: dest)

        #expect(!FileManager.default.fileExists(atPath: dest))
    }

    @Test("Copies when destination doesn't exist yet")
    func copiesWhenDestinationMissing() throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let source = (tempDir as NSString).appendingPathComponent("source-binary")
        let dest = (tempDir as NSString).appendingPathComponent("nonexistent-dest")

        try createBinary(at: source, size: 768)

        RefraxControlHost.copyBinary(from: source, to: dest)

        #expect(FileManager.default.fileExists(atPath: dest))
        let destData = try Data(contentsOf: URL(fileURLWithPath: dest))
        #expect(destData.count == 768)
    }
}

// MARK: - ControlAccessManager Auto-Allow Tests

/// Keeps the ModelContainer, BrowserSettings, and ControlAccessManager alive together.
/// BrowserSettings is held `unowned` by ControlAccessManager, so the container
/// must outlive the manager to avoid dangling references.
@MainActor
private struct ControlAccessTestEnvironment {
    let container: ModelContainer
    let settings: BrowserSettings
    let manager: ControlAccessManager

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        self.container = try ModelContainer(for: schema, configurations: [config])
        self.settings = BrowserSettings.fetchOrCreate(in: container.mainContext)
        self.manager = ControlAccessManager(settings: settings)
    }
}

@Suite("ControlAccessManager Auto-Allow", .tags(.cliInstaller), .serialized)
@MainActor
struct ControlAccessManagerAutoAllowTests {
    @Test("Includes /usr/local/bin/refrax-ctl in auto-allow list")
    func includesGlobalBinPath() throws {
        let env = try ControlAccessTestEnvironment()
        env.manager.autoAllowRefraxCTL()

        let paths = env.manager.allowedClients.map(\.path)
        #expect(paths.contains("/usr/local/bin/refrax-ctl"))
    }

    @Test("Includes App Support bin path in auto-allow list")
    func includesAppSupportBinPath() throws {
        let env = try ControlAccessTestEnvironment()
        env.manager.autoAllowRefraxCTL()

        let paths = env.manager.allowedClients.map(\.path)
        let expected = (Directories.appStorage.path as NSString).appendingPathComponent("bin/refrax-ctl")
        #expect(paths.contains(expected))
    }

    @Test("Includes bundle Helpers path in auto-allow list")
    func includesBundleHelpersPath() throws {
        let env = try ControlAccessTestEnvironment()
        env.manager.autoAllowRefraxCTL()

        let paths = env.manager.allowedClients.map(\.path)
        let expected = (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Helpers/refrax-ctl")
        #expect(paths.contains(expected))
    }

    @Test("Includes dev build paths in auto-allow list")
    func includesDevBuildPaths() throws {
        let env = try ControlAccessTestEnvironment()
        env.manager.autoAllowRefraxCTL()

        let paths = env.manager.allowedClients.map(\.path)
        let releasePath = "\(NSHomeDirectory())/Developer/Refrax/refrax-ctl/.build/release/refrax-ctl"
        let debugPath = "\(NSHomeDirectory())/Developer/Refrax/refrax-ctl/.build/debug/refrax-ctl"
        #expect(paths.contains(releasePath))
        #expect(paths.contains(debugPath))
    }

    @Test("autoAllowRefraxCTL adds exactly 5 known paths")
    func addsAllKnownPaths() throws {
        let env = try ControlAccessTestEnvironment()
        env.manager.autoAllowRefraxCTL()

        #expect(env.manager.allowedClients.count == 5)
    }

    @Test("autoAllowRefraxCTL is idempotent")
    func idempotent() throws {
        let env = try ControlAccessTestEnvironment()
        env.manager.autoAllowRefraxCTL()
        let countAfterFirst = env.manager.allowedClients.count

        env.manager.autoAllowRefraxCTL()
        let countAfterSecond = env.manager.allowedClients.count

        #expect(countAfterFirst == countAfterSecond)
    }

    @Test("All auto-allowed clients have display name 'refrax-ctl'")
    func displayNames() throws {
        let env = try ControlAccessTestEnvironment()
        env.manager.autoAllowRefraxCTL()

        for client in env.manager.allowedClients {
            #expect(client.displayName == "refrax-ctl")
        }
    }
}
