import Testing
@testable import Refrax

struct DetailTrayPresentationTests {
    @Test
    func `Geometry updates retain the current drawer presentation`() throws {
        var presentation = DetailTrayPresentation()
        for _ in 0 ..< 1000 {
            let transition = presentation.transition(toVisible: false)
            #expect(transition == nil)
        }
        let show = presentation.transition(toVisible: true)
        _ = try #require(show)
        for _ in 0 ..< 1000 {
            let transition = presentation.transition(toVisible: true)
            #expect(transition == nil)
        }
    }

    @Test
    func `Reopening a drawer invalidates its hide completion`() throws {
        var presentation = DetailTrayPresentation()
        let show = presentation.transition(toVisible: true)
        _ = try #require(show)
        let close = presentation.transition(toVisible: false)
        let hide = try #require(close)
        #expect(presentation.canFinishHiding(hide))
        let reopen = presentation.transition(toVisible: true)
        _ = try #require(reopen)
        #expect(!presentation.canFinishHiding(hide))
    }

    @Test
    func `Rapid close reopen close honors the latest animation`() throws {
        var presentation = DetailTrayPresentation()
        let show = presentation.transition(toVisible: true)
        _ = try #require(show)
        let close = presentation.transition(toVisible: false)
        let firstHide = try #require(close)
        let reopen = presentation.transition(toVisible: true)
        _ = try #require(reopen)
        let closeAgain = presentation.transition(toVisible: false)
        let lastHide = try #require(closeAgain)
        #expect(!presentation.canFinishHiding(firstHide))
        #expect(presentation.canFinishHiding(lastHide))
    }
}
