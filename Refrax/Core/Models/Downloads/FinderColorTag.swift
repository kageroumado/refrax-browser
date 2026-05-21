import AppKit
import SwiftUI

/// Finder color label tags that can be applied to files.
///
/// These correspond to macOS Finder's built-in color labels, accessible via
/// `URL.setResourceValue(_:forKey: .labelNumber)`.
enum FinderColorTag: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case red = 6
    case orange = 7

    var id: Int { rawValue }

    /// Display name for the color tag.
    var displayName: String {
        switch self {
        case .none: "None"
        case .gray: "Gray"
        case .green: "Green"
        case .purple: "Purple"
        case .blue: "Blue"
        case .yellow: "Yellow"
        case .red: "Red"
        case .orange: "Orange"
        }
    }

    /// SwiftUI color for preview/display.
    var color: Color {
        switch self {
        case .none: .clear
        case .gray: .gray
        case .green: Color(nsColor: .systemGreen)
        case .purple: Color(nsColor: .systemPurple)
        case .blue: Color(nsColor: .systemBlue)
        case .yellow: Color(nsColor: .systemYellow)
        case .red: Color(nsColor: .systemRed)
        case .orange: Color(nsColor: .systemOrange)
        }
    }

    /// Applies this color tag to a file URL.
    ///
    /// - Parameter url: The file URL to tag.
    /// - Throws: If the tag cannot be applied.
    func apply(to url: URL) throws {
        try (url as NSURL).setResourceValue(rawValue as NSNumber, forKey: .labelNumberKey)
    }

    /// Creates a tag from an optional Int value.
    ///
    /// - Parameter value: The raw value, or nil.
    /// - Returns: The corresponding tag, or `.none` if nil or invalid.
    static func from(_ value: Int?) -> FinderColorTag {
        guard let value else { return .none }
        return FinderColorTag(rawValue: value) ?? .none
    }
}

// MARK: - URL Extension

extension URL {
    /// Applies a Finder color tag to this file.
    ///
    /// - Parameter tag: The color tag to apply, or nil to remove.
    func applyFinderColorTag(_ tag: FinderColorTag?) {
        let tagValue = tag ?? .none
        do {
            try tagValue.apply(to: self)
        } catch {
            Logger.warning(
                "Failed to apply Finder color tag to \(lastPathComponent): \(error)",
                category: Logger.downloads,
            )
        }
    }

    /// Applies a Finder color tag by raw value.
    ///
    /// - Parameter tagValue: The raw tag value (0-7), or nil for no tag.
    func applyFinderColorTag(rawValue: Int?) {
        applyFinderColorTag(FinderColorTag.from(rawValue))
    }
}
