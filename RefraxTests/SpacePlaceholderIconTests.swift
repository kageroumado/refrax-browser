import Testing
@testable import Refrax

/// The icon a space with none chosen shows.
struct SpacePlaceholderIconTests {
    @Test
    func `A space named by number shows that number`() {
        #expect(Space.placeholderSymbol(name: "Space 1", position: 0) == "1.square")
        #expect(Space.placeholderSymbol(name: "Space 12", position: 3) == "12.square")
    }

    @Test
    func `A named space shows its initial`() {
        #expect(Space.placeholderSymbol(name: "Work", position: 1) == "w.square")
        #expect(Space.placeholderSymbol(name: " research", position: nil) == "r.square")
    }

    @Test
    func `A space with no letter to show falls back to its place in the list`() {
        #expect(Space.placeholderSymbol(name: "日本", position: 2) == "3.square")
        #expect(Space.placeholderSymbol(name: "", position: nil) == "square")
        #expect(Space.placeholderSymbol(name: "", position: 80) == "square")
    }
}
