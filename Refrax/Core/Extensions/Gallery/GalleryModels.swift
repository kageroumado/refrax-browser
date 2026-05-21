import Foundation

// MARK: - Gallery Extension

/// Metadata for an extension in the gallery.
struct GalleryExtension: Codable, Identifiable, Hashable, Sendable {
    /// Unique identifier in the gallery.
    let id: String

    /// Display name of the extension.
    let name: String

    /// Short description of what the extension does.
    let description: String

    /// Category for grouping in the gallery.
    let category: ExtensionCategory

    /// Where to download the extension from.
    let source: GalleryExtensionSource

    /// URL to the extension's icon.
    let iconURL: URL?

    /// Version string (e.g., "1.62.0").
    let version: String?

    /// Compatibility status with Refrax.
    let compatibility: CompatibilityStatus

    /// Whether this extension is featured/recommended.
    let isFeatured: Bool

    /// Whether this extension is bundled with Refrax and auto-installed.
    let isBundled: Bool

    /// Tags for search.
    let tags: [String]

    /// Popularity rank (lower = more popular).
    let popularityRank: Int

    // MARK: - Coding

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case category
        case source
        case iconURL
        case version
        case compatibility
        case isFeatured
        case isBundled
        case tags
        case popularityRank
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.category = try container.decode(ExtensionCategory.self, forKey: .category)
        self.source = try container.decode(GalleryExtensionSource.self, forKey: .source)
        self.iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
        self.version = try container.decodeIfPresent(String.self, forKey: .version)
        self.compatibility = try container.decode(CompatibilityStatus.self, forKey: .compatibility)
        self.isFeatured = try container.decode(Bool.self, forKey: .isFeatured)
        self.isBundled = try container.decodeIfPresent(Bool.self, forKey: .isBundled) ?? false
        self.tags = try container.decode([String].self, forKey: .tags)
        self.popularityRank = try container.decode(Int.self, forKey: .popularityRank)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: GalleryExtension, rhs: GalleryExtension) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Extension Category

/// Categories for organizing extensions in the gallery.
enum ExtensionCategory: String, Codable, CaseIterable, Sendable {
    case passwordManagers = "password_managers"
    case adsTracking = "ads_tracking"
    case productivity
    case privacy
    case development
    case socialMedia = "social_media"
    case shopping
    case entertainment
    case accessibility
    case other

    /// Display name for the category.
    var displayName: String {
        switch self {
        case .passwordManagers: "Password Managers"
        case .adsTracking: "Ads & Tracking"
        case .productivity: "Productivity"
        case .privacy: "Privacy"
        case .development: "Development"
        case .socialMedia: "Social Media"
        case .shopping: "Shopping"
        case .entertainment: "Entertainment"
        case .accessibility: "Accessibility"
        case .other: "Other"
        }
    }

    /// SF Symbol for the category.
    var icon: String {
        switch self {
        case .passwordManagers: "key.fill"
        case .adsTracking: "shield.slash"
        case .productivity: "checkmark.circle"
        case .privacy: "hand.raised.fill"
        case .development: "hammer.fill"
        case .socialMedia: "bubble.left.and.bubble.right.fill"
        case .shopping: "cart.fill"
        case .entertainment: "play.circle.fill"
        case .accessibility: "accessibility"
        case .other: "puzzlepiece.extension"
        }
    }
}

// MARK: - Gallery Extension Source

/// Where a gallery extension can be downloaded from.
enum GalleryExtensionSource: Codable, Hashable, Sendable {
    /// Chrome Web Store extension.
    case chrome(extensionID: String)

    /// Firefox Add-ons extension.
    case firefox(extensionID: String)

    /// Direct download URL.
    case directDownload(url: URL)

    /// Display name for the source.
    var displayName: String {
        switch self {
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .directDownload: "Direct Download"
        }
    }

    /// URL to the extension's store page.
    var storeURL: URL? {
        switch self {
        case let .chrome(extensionID):
            URL(string: "https://chromewebstore.google.com/detail/\(extensionID)")
        case let .firefox(extensionID):
            URL(string: "https://addons.mozilla.org/en-US/firefox/addon/\(extensionID)/")
        case .directDownload:
            nil
        }
    }
}

// MARK: - Compatibility Status

/// How well an extension works with Refrax.
enum CompatibilityStatus: String, Codable, Sendable {
    /// Fully tested and working.
    case verified

    /// Expected to work, not fully tested.
    case expected

    /// Partially working with known issues.
    case partial

    /// Not compatible.
    case incompatible

    /// Unknown compatibility.
    case unknown

    var displayName: String {
        switch self {
        case .verified: "Verified"
        case .expected: "Expected to Work"
        case .partial: "Partial Support"
        case .incompatible: "Not Compatible"
        case .unknown: "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .verified: "checkmark.seal.fill"
        case .expected: "checkmark.circle"
        case .partial: "exclamationmark.circle"
        case .incompatible: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }
}

// MARK: - Gallery Response

/// Response from the gallery API or local JSON.
struct GalleryResponse: Codable, Sendable, Equatable {
    /// Version of the gallery format.
    let version: Int

    /// When the gallery was last updated.
    let lastUpdated: Date

    /// All extensions in the gallery.
    let extensions: [GalleryExtension]
}

// MARK: - Web Store URLs

/// URLs for web extension stores.
enum WebStoreURL {
    static let chromeWebStore = URL.staticRequired("https://chromewebstore.google.com/")
    static let firefoxAddons = URL.staticRequired("https://addons.mozilla.org/en-US/firefox/extensions/")
}
