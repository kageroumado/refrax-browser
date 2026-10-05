import Foundation
import Testing
@testable import Refrax

@Suite("Reader Markdown export")
struct ReaderExportTests {
    private func article(content: String, title: String = "Title") -> ExtractedArticle {
        ExtractedArticle(
            title: title,
            byline: nil,
            content: content,
            textContent: "",
            excerpt: nil,
            siteName: nil,
            publishedTime: nil,
            sourceURL: URL(string: "https://example.com/post")!,
        )
    }

    private func markdown(_ content: String) async -> String {
        await ReaderExportService(article: article(content: content)).markdown()
    }

    @Test
    func `Tags after emoji and combining marks convert in place`() async {
        let result = await markdown("<p>👩‍👩‍👧 café́ 🇫🇷</p><p><strong>bold</strong> and <em>after</em></p>")

        #expect(result.hasSuffix("👩‍👩‍👧 café́ 🇫🇷\n\n**bold** and *after*"))
    }

    @Test
    func `Blockquotes after emoji convert in place`() async {
        let result = await markdown("<p>🧪🧪🧪</p><blockquote>quoted</blockquote><p>end</p>")

        #expect(result.hasSuffix("🧪🧪🧪\n\n> quoted\n\nend"))
    }

    @Test
    func `Numeric entities after emoji decode in place`() async {
        let result = await markdown("<p>🎌 &#65;&#66; tail</p>")

        #expect(result.hasSuffix("🎌 AB tail"))
    }

    @Test
    func `An escaped entity decodes once`() async {
        let result = await markdown("<p>&amp;lt;tag&amp;gt; &amp;amp; &amp;#39;</p>")

        #expect(result.hasSuffix("&lt;tag&gt; &amp; &#39;"))
    }

    @Test
    func `Markdown carries the title and the source`() async {
        let result = await markdown("<p>Body</p>")

        #expect(result.hasPrefix("# Title\n\n> Source: [example.com](https://example.com/post)\n"))
        #expect(result.hasSuffix("---\n\nBody"))
    }
}

@Suite("Speed Reader words")
struct SpeedReaderWordsTests {
    @Test
    func `Words come back with sentence and paragraph pauses`() async {
        let words = await SpeedReaderProcessor.words(in: "One, two.\n\nThree")

        #expect(words.map(\.text) == ["One", "two", "Three"])
        #expect(words.map(\.pauseMultiplier) == [1.5, 3.0, 1.0])
    }
}
