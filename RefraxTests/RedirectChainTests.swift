import Foundation
import Testing

@testable import Refrax

@Suite("RedirectChain", .tags(.navigation))
@MainActor
struct RedirectChainTests {
    @Test("Append tracks OAuth URLs")
    func appendTracksOAuthURLs() {
        var chain = RedirectChain()
        chain.append(URL(string: "https://accounts.google.com/o/oauth2/auth?response_type=code")!)
        chain.append(URL(string: "https://example.com/callback")!)

        #expect(chain.containsOAuthURL)
        #expect(chain.urls.count == 2)
    }

    @Test("Reset clears chain")
    func resetClearsChain() {
        var chain = RedirectChain()
        chain.append(URL(string: "https://example.com")!)
        chain.reset()

        #expect(chain.urls.isEmpty)
    }
}
