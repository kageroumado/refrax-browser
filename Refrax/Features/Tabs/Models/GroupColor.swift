import SwiftUI

/// Predefined color palette for tab groups, spaces, and other themed elements.
///
/// Each case maps to an adaptive asset catalog color with light/dark variants:
/// - **Main** (`Color("Name")`): 60 APCA contrast — primary accent
/// - **Alt** (`Color("NameAlt")`): 75 APCA contrast — secondary/background
///
/// Colors are defined in OKLCH and converted to Display P3 for the asset catalog.
enum GroupColor: String, CaseIterable, Codable, Sendable {
    case flamingo = "Flamingo"
    case coral = "Coral"
    case mahogany = "Mahogany"
    case avocado = "Avocado"
    case emerald = "Emerald"
    case turquoise = "Turquoise"
    case pelorus = "Pelorus"
    case steel = "Steel"
    case neon = "Neon"
    case violet = "Violet"
    case orchid = "Orchid"

    /// The adaptive SwiftUI color from the asset catalog.
    var color: Color { Color(rawValue) }

    /// The alternative (higher contrast) adaptive color.
    var altColor: Color { Color(rawValue + "Alt") }
}
