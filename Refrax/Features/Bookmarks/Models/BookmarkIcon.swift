import Foundation
import SwiftUI

/// Represents a custom icon for a bookmark or folder.
///
/// Supports three icon types:
/// - **SF Symbol**: System icon by name (e.g., "star.fill")
/// - **Emoji**: Single emoji character (e.g., "📚")
/// - **Custom Image**: User-uploaded PNG or SVG data
///
/// Icons are stored as strings for SF Symbols and emojis, or as `Data` for images.
/// The type is encoded as a JSON string for SwiftData persistence.
///
/// ## Usage
///
/// ```swift
/// let symbolIcon = BookmarkIcon.sfSymbol("star.fill")
/// let emojiIcon = BookmarkIcon.emoji("📚")
/// let imageIcon = BookmarkIcon.image(pngData)
/// ```
nonisolated enum BookmarkIcon: Codable, Equatable {
    case sfSymbol(String)
    case emoji(String)
    case image(Data)
    
    // MARK: - Coding Keys
    
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }
    
    private enum IconType: String, Codable {
        case sfSymbol
        case emoji
        case image
    }
    
    // MARK: - Codable
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(IconType.self, forKey: .type)
        
        switch type {
        case .sfSymbol:
            let name = try container.decode(String.self, forKey: .value)
            self = .sfSymbol(name)
        case .emoji:
            let emoji = try container.decode(String.self, forKey: .value)
            self = .emoji(emoji)
        case .image:
            let data = try container.decode(Data.self, forKey: .value)
            self = .image(data)
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case let .sfSymbol(name):
            try container.encode(IconType.sfSymbol, forKey: .type)
            try container.encode(name, forKey: .value)
        case let .emoji(emoji):
            try container.encode(IconType.emoji, forKey: .type)
            try container.encode(emoji, forKey: .value)
        case let .image(data):
            try container.encode(IconType.image, forKey: .type)
            try container.encode(data, forKey: .value)
        }
    }
    
    // MARK: - SwiftData Storage
    
    /// Encode to JSON string for SwiftData storage
    var jsonString: String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Decode from JSON string stored in SwiftData
    static func from(jsonString: String?) -> BookmarkIcon? {
        guard let jsonString,
              let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(BookmarkIcon.self, from: data)
    }
}

// MARK: - SwiftUI View Extension

extension BookmarkIcon {
    /// Create a SwiftUI view for this icon
    ///
    /// - Parameter size: Font size for SF Symbols and emojis, image size for custom images
    /// - Returns: A view displaying the icon
    @ViewBuilder
    func view(size: CGFloat = 24) -> some View {
        switch self {
        case let .sfSymbol(name):
            Image(systemName: name)
                .font(.system(size: size))
        case let .emoji(emoji):
            Text(emoji)
                .font(.system(size: size))
        case let .image(data):
            if let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: size))
            }
        }
    }
}

// MARK: - Validation

extension BookmarkIcon {
    /// Validate that an emoji string contains exactly one emoji character
    nonisolated static func isValidEmoji(_ string: String) -> Bool {
        guard string.count == 1 else { return false }
        return string.unicodeScalars.allSatisfy(\.properties.isEmoji)
    }
    
    /// Validate that an SF Symbol name exists in the system
    nonisolated static func isValidSFSymbol(_ name: String) -> Bool {
        NSImage(named: name) != nil
    }
    
    /// Validate that image data can be decoded
    nonisolated static func isValidImageData(_ data: Data) -> Bool {
        NSImage(data: data) != nil
    }
}
