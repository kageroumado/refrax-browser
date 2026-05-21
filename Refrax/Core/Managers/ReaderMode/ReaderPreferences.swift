import Foundation
import SwiftUI

/// User preferences for Reader Mode appearance.
///
/// Controls the visual presentation of extracted articles including
/// theme, typography, and layout. Persisted via UserDefaults.
struct ReaderPreferences: Codable, Equatable, Sendable {
    /// The color theme for the reader view.
    var theme: ReaderTheme = .auto

    /// Font size in points.
    var fontSize: Int = 18

    /// The font family to use.
    var fontFamily: ReaderFont = .system

    /// Line height multiplier (e.g., 1.6 = 160% of font size).
    var lineHeight: Double = 1.6

    /// Maximum content width in points.
    var maxWidth: Int = 680

    // MARK: - Persistence

    private static let userDefaultsKey = "ReaderPreferences"

    /// Loads preferences from UserDefaults.
    static func load() -> ReaderPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? JSONDecoder().decode(ReaderPreferences.self, from: data)
        else {
            return ReaderPreferences()
        }
        return prefs
    }

    /// Saves preferences to UserDefaults.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}

// MARK: - Theme

/// Color theme options for Reader Mode.
enum ReaderTheme: String, Codable, CaseIterable, Sendable {
    case auto
    case light
    case dark
    case sepia

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        case .sepia: "Sepia"
        }
    }

    var iconName: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        case .sepia: "book"
        }
    }

    /// Background color for the theme.
    func backgroundColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .auto:
            colorScheme == .dark ? Color(white: 0.1) : .white
        case .light:
            .white
        case .dark:
            Color(white: 0.1)
        case .sepia:
            Color(red: 0.98, green: 0.96, blue: 0.90)
        }
    }

    /// Text color for the theme.
    func textColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .auto:
            // swiftlint:disable:next void_function_in_ternary
            colorScheme == .dark ? Color(white: 0.9) : Color(white: 0.1)
        case .light:
            Color(white: 0.1)
        case .dark:
            Color(white: 0.9)
        case .sepia:
            Color(red: 0.35, green: 0.25, blue: 0.15)
        }
    }

    /// Link color for the theme.
    func linkColor(for _: ColorScheme) -> Color {
        switch self {
        case .auto:
            .appAccentColor
        case .light:
            Color(red: 0.0, green: 0.48, blue: 1.0)
        case .dark:
            Color(red: 0.4, green: 0.68, blue: 1.0)
        case .sepia:
            Color(red: 0.55, green: 0.35, blue: 0.1)
        }
    }
}

// MARK: - Font

/// Font family options for Reader Mode.
enum ReaderFont: String, Codable, CaseIterable, Sendable {
    case system
    case serif
    case sansSerif
    case mono

    var displayName: String {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .sansSerif: "Sans Serif"
        case .mono: "Monospace"
        }
    }

    /// The CSS font-family value.
    var cssFontFamily: String {
        switch self {
        case .system:
            "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
        case .serif:
            "Georgia, 'Times New Roman', Times, serif"
        case .sansSerif:
            "'Helvetica Neue', Helvetica, Arial, sans-serif"
        case .mono:
            "'SF Mono', Menlo, Monaco, 'Courier New', monospace"
        }
    }

    /// The SwiftUI Font.Design value.
    var fontDesign: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .sansSerif: .default
        case .mono: .monospaced
        }
    }
}
