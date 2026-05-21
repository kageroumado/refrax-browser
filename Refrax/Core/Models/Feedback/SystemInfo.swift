import Foundation

/// Automatically collected system context for feedback submissions.
///
/// Contains no PII -- only version numbers, hardware class, and aggregate
/// counts. Included with every feedback submission to help diagnose issues
/// without requiring back-and-forth with the user.
nonisolated struct SystemInfo: Codable, Sendable {
    let refraxVersion: String
    let refraxBuild: String
    let macOSVersion: String
    let hardwareModel: String
    let memoryGB: Int
    let locale: String
    let tabCount: Int
    let spaceCount: Int
    let extensionCount: Int
    let uptime: TimeInterval

    /// Collects current system information.
    ///
    /// Version and build come from the main bundle. Hardware details come
    /// from `ProcessInfo`. Tab, space, and extension counts are passed in
    /// from the calling context which has access to live managers.
    @MainActor
    static func collect(tabCount: Int, spaceCount: Int, extensionCount: Int) -> SystemInfo {
        let bundle = Bundle.main
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion

        var size: size_t = 0
        var hardwareModel = "Unknown"
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            let bytes = model.prefix(while: { $0 != 0 }).map(UInt8.init)
            hardwareModel = String(decoding: bytes, as: UTF8.self)
        }

        return SystemInfo(
            refraxVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            refraxBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            macOSVersion: "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
            hardwareModel: hardwareModel,
            memoryGB: Int(processInfo.physicalMemory / (1_024 * 1_024 * 1_024)),
            locale: Locale.current.identifier,
            tabCount: tabCount,
            spaceCount: spaceCount,
            extensionCount: extensionCount,
            uptime: processInfo.systemUptime,
        )
    }
}
