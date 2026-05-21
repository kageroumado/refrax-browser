import Foundation

// MARK: - App Group Identifier

/// The app group identifier used for sharing data between Refrax and its widgets.
///
/// On macOS, app groups use the Team ID prefix format.
/// When running without a team (local development), use the bundle ID based format.
enum RefraxAppGroup {
    static let identifier = "group.website.refrax.browser"

    /// Returns the URL for the shared container, or nil if unavailable.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Returns the URL for the widget data file.
    static var widgetDataURL: URL? {
        containerURL?.appendingPathComponent("widget-data.json")
    }
}

// MARK: - Widget Data Models

/// Data shared with widgets, serialized to JSON in the app group container.
struct RefraxWidgetData: Codable, Sendable {
    /// When this data was last updated.
    let lastUpdated: Date

    /// Browser health statistics from Air Traffic Control.
    let browserHealth: BrowserHealthData

    /// Information about the currently active tab.
    let currentTab: CurrentTabData?

    /// Top tabs by importance (for widget display).
    let topTabs: [TabSummary]

    /// Recent spaces for quick access.
    let recentSpaces: [SpaceSummary]
}

/// Browser health statistics matching Air Traffic Control data.
struct BrowserHealthData: Codable, Sendable {
    /// Total number of open tabs across all spaces.
    let totalTabCount: Int

    /// Number of spaces.
    let spaceCount: Int

    /// WebContent process memory in megabytes.
    let webContentMemoryMB: Double

    /// Number of active WebContent processes.
    let activeProcessCount: Int

    /// Number of crashed tabs.
    let crashedTabCount: Int

    /// Number of suspended tabs.
    let suspendedTabCount: Int

    /// Number of tabs playing audio.
    let playingAudioCount: Int

    /// Number of tabs with active media capture (camera/mic).
    let mediaCaptureCount: Int
}

/// Summary of the currently active tab.
struct CurrentTabData: Codable, Sendable {
    /// Tab title.
    let title: String

    /// Tab URL.
    let url: URL

    /// Domain extracted from URL.
    let domain: String

    /// Space name the tab belongs to.
    let spaceName: String

    /// Whether the tab is playing audio.
    let isPlayingAudio: Bool

    /// Base64-encoded favicon data (PNG), if available.
    let faviconBase64: String?
}

/// Lightweight tab summary for widget display.
struct TabSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let domain: String
    let spaceName: String
    let isPlayingAudio: Bool
    let hasCrashed: Bool
    let importanceScore: Int
    let faviconBase64: String?
}

/// Space summary for quick access widget.
struct SpaceSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let iconName: String
    let tabCount: Int
    let colorHex: String?
}

// MARK: - Widget Data Storage

/// Handles reading and writing widget data to the shared container.
enum WidgetDataStorage {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Writes widget data to the shared container.
    static func write(_ data: RefraxWidgetData) throws {
        guard let url = RefraxAppGroup.widgetDataURL else {
            throw WidgetDataError.containerUnavailable
        }

        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url, options: .atomic)
    }

    /// Reads widget data from the shared container.
    static func read() -> RefraxWidgetData? {
        guard let url = RefraxAppGroup.widgetDataURL,
              let jsonData = try? Data(contentsOf: url) else {
            return nil
        }

        return try? decoder.decode(RefraxWidgetData.self, from: jsonData)
    }

    /// Returns sample data for widget previews.
    static var sampleData: RefraxWidgetData {
        RefraxWidgetData(
            lastUpdated: Date(),
            browserHealth: BrowserHealthData(
                totalTabCount: 42,
                spaceCount: 5,
                webContentMemoryMB: 1_247.5,
                activeProcessCount: 12,
                crashedTabCount: 0,
                suspendedTabCount: 8,
                playingAudioCount: 1,
                mediaCaptureCount: 0,
            ),
            currentTab: CurrentTabData(
                title: "Apple Developer Documentation",
                url: URL(string: "https://developer.apple.com/documentation") ?? URL(fileURLWithPath: "/"),
                domain: "developer.apple.com",
                spaceName: "Work",
                isPlayingAudio: false,
                faviconBase64: nil,
            ),
            topTabs: [
                TabSummary(
                    id: UUID(),
                    title: "GitHub",
                    domain: "github.com",
                    spaceName: "Work",
                    isPlayingAudio: false,
                    hasCrashed: false,
                    importanceScore: 850,
                    faviconBase64: nil,
                ),
                TabSummary(
                    id: UUID(),
                    title: "YouTube Music",
                    domain: "music.youtube.com",
                    spaceName: "Personal",
                    isPlayingAudio: true,
                    hasCrashed: false,
                    importanceScore: 1_200,
                    faviconBase64: nil,
                ),
            ],
            recentSpaces: [
                SpaceSummary(id: UUID(), name: "Work", iconName: "briefcase", tabCount: 15, colorHex: "#007AFF"),
                SpaceSummary(id: UUID(), name: "Personal", iconName: "person", tabCount: 12, colorHex: "#34C759"),
                SpaceSummary(id: UUID(), name: "Research", iconName: "book", tabCount: 8, colorHex: "#FF9500"),
            ],
        )
    }
}

enum WidgetDataError: Error {
    case containerUnavailable
}
