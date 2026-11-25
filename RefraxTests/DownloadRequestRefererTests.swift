import Foundation
import Testing
@testable import Refrax

/// A download is re-requested by Refrax, not WebKit, and must carry the Referer WebKit would
/// have sent: hotlink-protected hosts redirect a bare request to an HTML page.
@Suite("Download Request Referer", .tags(.downloadManager))
struct DownloadRequestRefererTests {
    private let gelbooruPost = URL(string: "https://gelbooru.com/index.php?page=post&s=view&id=15318624#comments")!
    private let gelbooruImage = URL(string: "https://img4.gelbooru.com/images/eb/37/eb37e3cf1f5fcd894abf3df13dca897f.jpg")!

    @Test
    func `An image saved from a post page is requested with the page's origin as Referer`() {
        let request = DownloadTask.request(for: gelbooruImage, from: gelbooruPost)

        #expect(request.url == gelbooruImage)
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://gelbooru.com/")
    }

    @Test
    func `A file on the page's own origin gets the full page address without its fragment`() throws {
        let file = try #require(URL(string: "https://gelbooru.com/images/eb/37/file.jpg"))

        #expect(DownloadTask.referer(forRequestTo: file, from: gelbooruPost)
            == "https://gelbooru.com/index.php?page=post&s=view&id=15318624")
    }

    @Test
    func `Credentials in the page address never reach the Referer`() throws {
        let page = try #require(URL(string: "https://user:secret@example.com/a?b=c"))

        #expect(DownloadTask.referer(forRequestTo: gelbooruImage, from: page) == "https://example.com/")
    }

    @Test
    func `A different port is another origin`() throws {
        let page = try #require(URL(string: "https://example.com:8443/gallery"))
        let file = try #require(URL(string: "https://example.com/file.jpg"))
        let sameOriginFile = try #require(URL(string: "https://example.com:8443/file.jpg"))

        #expect(DownloadTask.referer(forRequestTo: file, from: page) == "https://example.com:8443/")
        #expect(DownloadTask.referer(forRequestTo: sameOriginFile, from: page) == "https://example.com:8443/gallery")
    }

    @Test
    func `No Referer goes from an HTTPS page to an HTTP file`() throws {
        let file = try #require(URL(string: "http://img4.gelbooru.com/images/file.jpg"))

        #expect(DownloadTask.referer(forRequestTo: file, from: gelbooruPost) == nil)
    }

    @Test
    func `No Referer goes without a web page to name`() throws {
        #expect(DownloadTask.referer(forRequestTo: gelbooruImage, from: nil) == nil)
        #expect(try DownloadTask.referer(forRequestTo: gelbooruImage, from: #require(URL(string: "about:blank"))) == nil)
        #expect(try DownloadTask.referer(forRequestTo: gelbooruImage, from: #require(URL(string: "file:///tmp/a.html"))) == nil)
        #expect(DownloadTask.request(for: gelbooruImage, from: nil).value(forHTTPHeaderField: "Referer") == nil)
    }
}
