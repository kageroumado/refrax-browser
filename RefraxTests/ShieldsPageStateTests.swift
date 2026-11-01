import Testing
@testable import Refrax

@Suite("Shields page state", .tags(.shields))
struct ShieldsPageStateTests {
    @Test
    func `A site Shields is off for shows as off on its pages and subdomains`() {
        let state = ShieldsPageState(isEnabled: true, host: "www.youtube.com", offSites: ["youtube.com"], blocked: 12)
        #expect(state == .offForSite(site: "youtube.com"))
        #expect(!state.isFiltering)
        #expect(state.badge == nil, "a stale count never hides the off state")
        #expect(state.symbolName == "shield.slash.fill")
        #expect(state.title == "Shields is off for youtube.com")
        #expect(state.offExplanation != nil)

        #expect(ShieldsPageState(isEnabled: true, host: "YouTube.com", offSites: ["youtube.com"], blocked: 0) == .offForSite(site: "youtube.com"))
        #expect(ShieldsPageState(isEnabled: true, host: "notyoutube.com", offSites: ["youtube.com"], blocked: 0) == .on(blocked: 0))
        #expect(ShieldsPageState(isEnabled: true, host: "music.youtube.com", offSites: ["example.com", "youtube.com"], blocked: 0)
            == .offForSite(site: "youtube.com"))
    }

    @Test
    func `The global switch off outranks the site and the count`() {
        let state = ShieldsPageState(isEnabled: false, host: "www.youtube.com", offSites: ["youtube.com"], blocked: 3)
        #expect(state == .off)
        #expect(state.title == "Shields is off")
        #expect(state.badge == nil)
        #expect(state.offExplanation != nil)
        #expect(ShieldsPageState(isEnabled: false, host: nil, offSites: [], blocked: 0) == .off)
    }

    @Test
    func `On, the control counts what Shields blocked`() {
        #expect(ShieldsPageState(isEnabled: true, host: "example.com", offSites: [], blocked: 0).badge == nil)
        #expect(ShieldsPageState(isEnabled: true, host: "example.com", offSites: [], blocked: 1).title == "Shields blocked 1 load")
        #expect(ShieldsPageState(isEnabled: true, host: "example.com", offSites: [], blocked: 7).badge == "7")
        #expect(ShieldsPageState(isEnabled: true, host: "example.com", offSites: [], blocked: 250).badge == "99+")
        #expect(ShieldsPageState(isEnabled: true, host: nil, offSites: ["example.com"], blocked: 2).isFiltering)
        #expect(ShieldsPageState(isEnabled: true, host: "example.com", offSites: [], blocked: 2).symbolName == "shield.lefthalf.filled")
    }
}
