import Foundation

/// Resolves the best available path for a bundled binary, picking the
/// highest version between the app-bundled copy and any user-installed one.
///
/// Both aria2c and yt-dlp are bundled in `Contents/Resources/Binaries/`.
/// If the user has a newer version installed (e.g. via Homebrew), we use that instead.
nonisolated enum BundledBinaryResolver {

    /// Finds the best binary, preferring whichever has the higher version.
    ///
    /// Discovery:
    /// 1. Look for the bundled binary in `Resources/Binaries/`
    /// 2. Check well-known system paths + `PATH` lookup
    /// 3. If both exist, compare versions and return the higher one
    /// 4. If versions can't be determined, prefer bundled
    ///
    /// - Parameters:
    ///   - resourceName: The binary filename (e.g. `"aria2c"`, `"yt-dlp"`).
    ///   - systemPaths: Well-known installation paths to check.
    ///   - versionParser: Extracts a comparable version array from `--version` output.
    /// - Returns: The resolved binary path, or `nil` if not found anywhere.
    static func resolve(
        resourceName: String,
        systemPaths: [String],
        versionParser: (String) -> [Int]?,
    ) -> String? {
        let bundledPath = findBundled(resourceName)
        let systemPath = findSystem(resourceName, paths: systemPaths)

        switch (bundledPath, systemPath) {
        case let (bundled?, nil):
            return bundled
        case let (nil, system?):
            return system
        case let (bundled?, system?):
            return pickHigherVersion(
                bundled: bundled,
                system: system,
                versionParser: versionParser,
            )
        case (nil, nil):
            return nil
        }
    }

    // MARK: - Discovery

    private static func findBundled(_ name: String) -> String? {
        guard let path = Bundle.main.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Binaries",
        )?.path else { return nil }

        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private static func findSystem(_ name: String, paths: [String]) -> String? {
        let fm = FileManager.default

        for path in paths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        return findInPATH(name)
    }

    private static func findInPATH(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty,
                FileManager.default.isExecutableFile(atPath: path) else { return nil }

            return path
        } catch {
            return nil
        }
    }

    // MARK: - Version Comparison

    private static func pickHigherVersion(
        bundled: String,
        system: String,
        versionParser: (String) -> [Int]?,
    ) -> String {
        guard let bundledVersion = queryVersion(at: bundled, parser: versionParser),
              let systemVersion = queryVersion(at: system, parser: versionParser) else {
            return bundled
        }

        return compareVersions(bundledVersion, systemVersion) >= 0 ? bundled : system
    }

    private static func queryVersion(
        at path: String,
        parser: (String) -> [Int]?,
    ) -> [Int]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return parser(output)
        } catch {
            return nil
        }
    }

    /// Compares two version arrays lexicographically.
    ///
    /// Returns positive if `a > b`, negative if `a < b`, zero if equal.
    private static func compareVersions(_ a: [Int], _ b: [Int]) -> Int {
        let length = max(a.count, b.count)
        for i in 0..<length {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av - bv }
        }
        return 0
    }

    // MARK: - Version Parsers

    /// Parses aria2c version from `"aria2 version 1.37.0\n..."` → `[1, 37, 0]`.
    static func parseAria2Version(_ output: String) -> [Int]? {
        guard let firstLine = output.split(separator: "\n").first,
              let versionString = firstLine.split(separator: " ").last else { return nil }
        return parseComponents(String(versionString))
    }

    /// Parses yt-dlp version from `"2026.03.17\n"` → `[2026, 3, 17]`.
    static func parseYTDLPVersion(_ output: String) -> [Int]? {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseComponents(line)
    }

    private static func parseComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return parts.isEmpty ? nil : parts
    }
}
