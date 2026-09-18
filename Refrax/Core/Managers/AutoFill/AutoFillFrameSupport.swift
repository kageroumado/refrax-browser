import CoreGraphics
import Foundation
import WebKit

// Pure helpers for autofill across frame boundaries.
//
// A login form served from a cross-origin iframe (Apple ID's `idmsa.apple.com`
// widget inside `appleid.apple.com`, embedded SSO, some 3-D-Secure flows) is
// invisible to any script that only inspects the main frame. Filling and
// positioning such a field needs two coordinate/identity translations, both of
// which are pure and live here so they can be unit-tested without WebKit.

/// Translates a sub-frame field's geometry into the top web view's coordinates.
nonisolated enum AutoFillFrameGeometry {
    /// The field rect measured inside the sub-frame, shifted by the origin of the
    /// sub-frame's `<iframe>` content box within the top web view.
    ///
    /// - Parameters:
    ///   - fieldRectInFrame: `getBoundingClientRect()` of the field, in the sub-frame's viewport.
    ///   - frameOrigin: Top-left of the iframe's content box in the top web view (border + padding included).
    static func rectInTopView(fieldRectInFrame: CGRect, frameOrigin: CGPoint) -> CGRect {
        CGRect(
            x: fieldRectInFrame.origin.x + frameOrigin.x,
            y: fieldRectInFrame.origin.y + frameOrigin.y,
            width: fieldRectInFrame.width,
            height: fieldRectInFrame.height,
        )
    }
}

/// Resolves which URL a credential seen in a sub-frame belongs to.
enum AutoFillDomain {
    /// The URL a credential submitted through a sub-frame should be saved and looked up under.
    ///
    /// A same-site sub-frame — the auth widget an operator embeds on its own eTLD+1,
    /// e.g. `idmsa.apple.com` inside `appleid.apple.com` — is keyed to the top-level
    /// host the user recognizes, so the saved entry round-trips with what they see in
    /// the address bar. A genuinely third-party embedded login (a different eTLD+1)
    /// keeps its own frame host, since the credential is the identity provider's.
    ///
    /// `@MainActor` because eTLD+1 resolution reads the shared public-suffix list.
    @MainActor
    static func submissionURL(topLevel: URL?, frame: URL) -> URL {
        guard let topLevel,
              let topRegistrable = topLevel.registrableDomain?.lowercased(),
              let frameRegistrable = frame.registrableDomain?.lowercased(),
              topRegistrable == frameRegistrable
        else {
            return frame
        }
        return topLevel
    }
}

// MARK: - HTML Input Type Mapping

extension WKInputType {
    /// Maps an HTML `input.type` string to WebKit's focused-element input type.
    ///
    /// Unknown or absent types resolve to `.text`, matching the browser's own
    /// default for an `<input>` with no explicit type.
    nonisolated init(htmlType: String) {
        switch htmlType.lowercased() {
        case "password": self = .password
        case "email": self = .email
        case "tel": self = .phone
        case "url": self = .URL
        case "number": self = .number
        case "search": self = .search
        case "date": self = .date
        case "datetime-local": self = .dateTimeLocal
        case "month": self = .month
        case "week": self = .week
        case "time": self = .time
        case "color": self = .color
        default: self = .text
        }
    }
}
