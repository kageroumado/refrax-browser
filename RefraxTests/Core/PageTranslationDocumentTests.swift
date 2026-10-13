import Foundation
import Testing
@testable import Refrax

/// A translation is written back only into the document its text was read from.
struct PageTranslationDocumentTests {
    private let page = NSObject()
    private let otherPage = NSObject()
    private let url = URL(string: "https://a.example/article")!

    private func document(page: NSObject? = nil, url: URL? = nil, navigation: UInt64 = 1) -> PageTranslation.Document {
        PageTranslation.Document(page: ObjectIdentifier(page ?? self.page), url: url ?? self.url, navigation: navigation)
    }

    @Test
    func `the same page, address, and load is the same document`() {
        #expect(document() == document())
    }

    @Test
    func `another address in the same page is another document`() throws {
        #expect(try document() != document(url: #require(URL(string: "https://b.example/"))))
    }

    @Test
    func `a new load of the same address is another document`() {
        #expect(document() != document(navigation: 2))
    }

    @Test
    func `the same address in another page is another document`() {
        #expect(document() != document(page: otherPage))
    }
}
