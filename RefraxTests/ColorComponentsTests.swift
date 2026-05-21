import AppKit
import SwiftUI
import Testing

@testable import Refrax

@Suite("Color.Components P3 Support")
@MainActor
struct ColorComponentsTests {
    // MARK: - Tagged Format Encoding

    @Test("sRGB color encodes as srgb-tagged string")
    func srgbEncoding() {
        let c = Color.Components(red: 1, green: 0, blue: 0, colorSpace: .sRGB)
        #expect(c.taggedString == "srgb:1.0000,0.0000,0.0000")
    }

    @Test("P3 color encodes as p3-tagged string")
    func p3Encoding() {
        let c = Color.Components(red: 0.2706, green: 0.0196, blue: 0.8745, colorSpace: .displayP3)
        #expect(c.taggedString == "p3:0.2706,0.0196,0.8745")
    }

    @Test("Alpha included when not 1.0")
    func alphaEncoding() {
        let c = Color.Components(red: 1, green: 0, blue: 0, alpha: 0.5, colorSpace: .displayP3)
        #expect(c.taggedString == "p3:1.0000,0.0000,0.0000,0.5000")
    }

    // MARK: - Tagged Format Decoding

    @Test("Decode sRGB tagged string")
    func decodeSrgbTagged() {
        let c = Color.Components(encoded: "srgb:1.0000,0.0000,0.0000")
        #expect(c != nil)
        #expect(c?.colorSpace == .sRGB)
        #expect(c?.red == 1.0)
    }

    @Test("Decode P3 tagged string")
    func decodeP3Tagged() {
        let c = Color.Components(encoded: "p3:0.2706,0.0196,0.8745")
        #expect(c != nil)
        #expect(c?.colorSpace == .displayP3)
        #expect(((c?.blue ?? 0) - 0.8745).magnitude < 0.0001)
    }

    @Test("Decode tagged string with alpha")
    func decodeTaggedWithAlpha() {
        let c = Color.Components(encoded: "p3:1.0000,0.0000,0.0000,0.5000")
        #expect(c != nil)
        #expect(((c?.alpha ?? 0) - 0.5).magnitude < 0.0001)
    }

    // MARK: - Legacy Hex Fallback

    @Test("Decode legacy hex as sRGB")
    func decodeLegacyHex() {
        let c = Color.Components(encoded: "#FF0000")
        #expect(c != nil)
        #expect(c?.colorSpace == .sRGB)
        #expect(c?.red == 1.0)
        #expect(c?.green == 0.0)
        #expect(c?.blue == 0.0)
    }

    @Test("Decode legacy hex with alpha")
    func decodeLegacyHexAlpha() {
        let c = Color.Components(encoded: "#FF000080")
        #expect(c != nil)
        #expect(c?.colorSpace == .sRGB)
        #expect(((c?.alpha ?? 0) - 0.502).magnitude < 0.01)
    }

    // MARK: - Round-Trip

    @Test("sRGB round-trip through tagged format")
    func srgbRoundTrip() {
        let original = Color.Components(red: 0.5, green: 0.25, blue: 0.75, colorSpace: .sRGB)
        let decoded = Color.Components(encoded: original.taggedString)
        #expect(decoded?.colorSpace == .sRGB)
        #expect(((decoded?.red ?? 0) - 0.5).magnitude < 0.001)
        #expect(((decoded?.green ?? 0) - 0.25).magnitude < 0.001)
        #expect(((decoded?.blue ?? 0) - 0.75).magnitude < 0.001)
    }

    @Test("P3 round-trip through tagged format")
    func p3RoundTrip() {
        let original = Color.Components(red: 0.2706, green: 0.0196, blue: 0.8745, colorSpace: .displayP3)
        let decoded = Color.Components(encoded: original.taggedString)
        #expect(decoded?.colorSpace == .displayP3)
        #expect(((decoded?.red ?? 0) - 0.2706).magnitude < 0.001)
    }

    // MARK: - Equality

    @Test("Same RGBA different color space are not equal")
    func differentColorSpaceNotEqual() {
        let srgb = Color.Components(red: 1, green: 0, blue: 0, colorSpace: .sRGB)
        let p3 = Color.Components(red: 1, green: 0, blue: 0, colorSpace: .displayP3)
        #expect(srgb != p3)
    }

    @Test("Same RGBA same color space are equal")
    func sameColorSpaceEqual() {
        let a = Color.Components(red: 1, green: 0, blue: 0, colorSpace: .displayP3)
        let b = Color.Components(red: 1, green: 0, blue: 0, colorSpace: .displayP3)
        #expect(a == b)
    }

    // MARK: - NSColor Conversion

    @Test("P3 NSColor preserves color space")
    func p3NsColorPreservesSpace() {
        let nsColor = NSColor(displayP3Red: 0.5, green: 0.2, blue: 0.8, alpha: 1)
        let components = Color.Components(nsColor: nsColor)
        #expect(components.colorSpace == .displayP3)
        #expect((components.red - 0.5).magnitude < 0.001)
    }

    @Test("sRGB NSColor tagged as sRGB")
    func srgbNsColorTaggedCorrectly() {
        let nsColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let components = Color.Components(nsColor: nsColor)
        #expect(components.colorSpace == .sRGB)
    }

    @Test("P3 NSColor round-trips through Components")
    func p3NsColorRoundTrip() {
        let original = NSColor(displayP3Red: 0.3, green: 0.7, blue: 0.1, alpha: 0.9)
        let components = Color.Components(nsColor: original)
        let restored = components.nsColor
        let restoredP3 = restored.usingColorSpace(.displayP3)!
        #expect((restoredP3.redComponent - 0.3).magnitude < 0.001)
        #expect((restoredP3.greenComponent - 0.7).magnitude < 0.001)
        #expect((restoredP3.blueComponent - 0.1).magnitude < 0.001)
    }

    // MARK: - CGColor Conversion

    @Test("P3 Components produce P3 CGColor")
    func p3CgColor() {
        let c = Color.Components(red: 0.5, green: 0.5, blue: 0.5, colorSpace: .displayP3)
        let cgColor = c.cgColor
        #expect(cgColor.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test("sRGB Components produce sRGB CGColor")
    func srgbCgColor() {
        let c = Color.Components(red: 0.5, green: 0.5, blue: 0.5, colorSpace: .sRGB)
        let cgColor = c.cgColor
        #expect(cgColor.colorSpace?.name == CGColorSpace.sRGB)
    }

    // MARK: - hexString

    @Test("hexString is always sRGB representation")
    func hexStringAlwaysSrgb() {
        let c = Color.Components(red: 1, green: 0, blue: 0, colorSpace: .displayP3)
        #expect(c.hexString == "#FF0000")
    }

    // MARK: - Invalid Input

    @Test("Invalid encoded string returns nil")
    func invalidEncoded() {
        #expect(Color.Components(encoded: "invalid") == nil)
        #expect(Color.Components(encoded: "xyz:1,2,3") == nil)
        #expect(Color.Components(encoded: "") == nil)
    }
}
