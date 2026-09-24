import WebKit

// MARK: - Agent Perception

extension WebPage {
    /// The page's content as a tree of addressable elements, for agents and automation.
    ///
    /// Throws ``EngineError/unsupported(_:)`` while an engine without agent perception renders the page.
    func perceive() async throws -> PageContentTree {
        guard enginePage == nil else { throw EngineError.unsupported(.agentPerception) }
        return try await PageContentExtractor.extract(from: backingWebView, url: url ?? .blank, title: title)
    }

    /// Performs a native interaction (click, focus, text entry) on the page.
    func performInteraction(_ interaction: _WKTextExtractionInteraction) async throws {
        guard enginePage == nil else { throw EngineError.unsupported(.agentPerception) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            backingWebView._performInteraction(interaction) { result in
                if let error = result.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Dismisses the find-in-page UI and its highlights.
    func hideFindUI() {
        if let enginePage {
            enginePage.perform(.stopFinding)
        } else {
            backingWebView._hideFindUI()
        }
    }
}
