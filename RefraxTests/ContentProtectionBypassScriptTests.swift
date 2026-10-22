import Foundation
import Testing
import WebKit

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for the content protection bypass script.
    @Tag static var contentProtectionBypass: Self
}

// MARK: - Drag Tests

/// Runs the bypass script in a real web view and fires `dragstart` at page elements.
@Suite("ContentProtectionBypassScript drags", .tags(.contentProtectionBypass), .serialized)
@MainActor
struct ContentProtectionBypassScriptDragTests {
    private static let page = """
    <div id="slider" draggable="true"><div id="handle">volume</div></div>
    <div id="inline" draggable="true" ondragstart="window.inlineRan = true">card</div>
    <p id="plain" ondragstart="return false">text</p>
    <img id="image" src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">
    <script>
        document.getElementById('slider').addEventListener('dragstart', e => {
            e.preventDefault();
            window.sliderRan = true;
        });
        document.getElementById('image').addEventListener('dragstart', () => {
            window.imageRan = true;
        });
    </script>
    """

    /// A web view showing `page` with the bypass script applied.
    private func makeWebView() async throws -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://example.com/"))
        // The blank page the web view starts on is already complete, so wait for this page's elements
        let isLoaded = "document.readyState === 'complete' && document.getElementById('image') !== null"
        for _ in 0 ..< 250 {
            if try await webView.evaluateJavaScript(isLoaded) as? Bool == true {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try await webView.evaluateJavaScript(ContentProtectionBypassScript.script)
        return webView
    }

    private func fireDragStart(at id: String, in webView: WKWebView) async throws -> Bool {
        let script = """
        const event = new DragEvent('dragstart', { bubbles: true, cancelable: true });
        document.getElementById(id).dispatchEvent(event);
        return event.defaultPrevented;
        """
        return try await webView.callAsyncJavaScript(script, arguments: ["id": id], contentWorld: .page) as? Bool ?? false
    }

    @Test("A drag inside an element the page made draggable reaches the page's handler")
    func pageDraggableReachesHandler() async throws {
        let webView = try await makeWebView()

        let prevented = try await fireDragStart(at: "handle", in: webView)

        #expect(prevented, "The page cancels the native drag to run its own slider")
        #expect(try await webView.evaluateJavaScript("window.sliderRan === true") as? Bool == true)
    }

    @Test("A drag of an element the page didn't make draggable stays neutralized")
    func otherDragsStayNeutralized() async throws {
        let webView = try await makeWebView()

        _ = try await fireDragStart(at: "image", in: webView)

        #expect(try await webView.evaluateJavaScript("window.imageRan === true") as? Bool == false)
    }

    @Test("Inline ondragstart is kept only on elements the page made draggable")
    func inlineHandlersKeptOnDraggables() async throws {
        let webView = try await makeWebView()

        #expect(try await webView.evaluateJavaScript("document.getElementById('inline').hasAttribute('ondragstart')") as? Bool == true)
        #expect(try await webView.evaluateJavaScript("document.getElementById('plain').hasAttribute('ondragstart')") as? Bool == false)

        _ = try await fireDragStart(at: "inline", in: webView)
        #expect(try await webView.evaluateJavaScript("window.inlineRan === true") as? Bool == true)
    }
}
