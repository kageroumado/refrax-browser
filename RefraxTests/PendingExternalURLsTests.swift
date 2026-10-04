import Foundation
import Testing
@testable import Refrax

@Suite("PendingExternalURLs", .tags(.navigation))
@MainActor
struct PendingExternalURLsTests {
    private static func request(_ string: String, from source: String? = nil) -> PendingExternalURLs.Request {
        PendingExternalURLs.Request(url: URL(string: string)!, sourceAppBundleID: source)
    }

    @Test
    func `Requests admitted before opening are held, then returned in arrival order`() {
        var gate = PendingExternalURLs()
        let first = Self.request("https://example.com/a", from: "com.apple.mail")
        let second = Self.request("https://example.com/b")

        #expect(gate.admit(first) == nil)
        #expect(gate.admit(second) == nil)
        #expect(gate.open() == [first, second])
    }

    @Test
    func `Requests admitted after opening pass straight through`() {
        var gate = PendingExternalURLs()
        _ = gate.open()
        let request = Self.request("https://example.com/c", from: "com.tinyspeck.slackmacgap")

        #expect(gate.isOpen)
        #expect(gate.admit(request) == request)
    }

    @Test
    func `Held requests are delivered once`() {
        var gate = PendingExternalURLs()
        _ = gate.admit(Self.request("https://example.com/d"))

        #expect(gate.open().count == 1)
        #expect(gate.open().isEmpty)
    }
}
