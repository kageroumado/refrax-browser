import AppKit
import Testing
@testable import Refrax

@MainActor
struct FloatingRegionTests {
    @Test
    func `drawing beyond the viewport keeps a finite reachable frame`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        let selection = FloatingRegionSelection(
            tab: tab,
            pageFrame: .zero,
            viewportSize: CGSize(width: 1_000, height: 800),
            documentRevision: UUID(),
        )
        #expect(selection.boundedRect(from: CGPoint(x: -100, y: -100), to: CGPoint(x: -20, y: -30)) == .zero)
        #expect(selection.boundedRect(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 1_200, y: 900))
            == CGRect(x: 400, y: 300, width: 600, height: 500))
    }

    @Test
    func `region scaling keeps pointer coordinates and resizing reveals more content`() throws {
        let region = try FloatingPageRegion(
            sourceURL: #require(URL(string: "https://example.com")),
            viewportSize: CGSize(width: 1_600, height: 1_000),
            rect: CGRect(x: 300, y: 200, width: 400, height: 300),
            scale: 0.5,
        )
        let content = DesktopContentView()
        let preview = FloatingPreviewScaleView(content: content, viewportSize: region.viewportSize)
        preview.region = region
        preview.frame = CGRect(x: 0, y: 0, width: 200, height: 150)
        preview.layoutSubtreeIfNeeded()
        let point = content.convert(CGPoint(x: 50, y: 50), from: preview)
        #expect(abs(point.x - 400) < 0.01)
        #expect(abs(point.y - 300) < 0.01)
        preview.frame.size = CGSize(width: 400, height: 300)
        preview.needsLayout = true
        preview.layoutSubtreeIfNeeded()
        #expect(content.convert(CGPoint(x: 50, y: 50), from: preview) == point)
        #expect(content.bounds.size == region.viewportSize)
    }

    @Test
    func `crop survives a shape change and placements decode`() throws {
        let data = Data(#"{"x":0.2,"y":0.3,"shape":"tab","isPinned":false}"#.utf8)
        var placement = try JSONDecoder().decode(FloatingTabPlacement.self, from: data)
        #expect(placement.region == nil)
        placement.region = try FloatingPageRegion(
            sourceURL: #require(URL(string: "https://example.com")),
            viewportSize: CGSize(width: 1_000, height: 800),
            rect: CGRect(x: 50, y: 80, width: 400, height: 200),
        )
        placement.setShape(.icon, in: CGRect(x: 0, y: 0, width: 1_000, height: 800))
        let restored = try JSONDecoder().decode(FloatingTabPlacement.self, from: JSONEncoder().encode(placement))
        #expect(restored.region == placement.region)
        #expect(restored.region?.isValid == true)
    }

    private final class DesktopContentView: NSView {
        override var isFlipped: Bool {
            true
        }
    }

    @Test
    func `invalid or outside crop is refused`() throws {
        var region = try FloatingPageRegion(
            sourceURL: #require(URL(string: "https://example.com")),
            viewportSize: CGSize(width: 1_000, height: 800),
            rect: CGRect(x: 900, y: 0, width: 400, height: 200),
        )
        #expect(!region.isValid)
        region.rect = CGRect(x: 0, y: 0, width: 300, height: 200)
        region.scale = .nan
        #expect(!region.isValid)
    }
}
