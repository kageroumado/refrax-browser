import Foundation

/// Two local pages for learning placement, Look, and live previews with real input.
enum FloatingTabsTutorial {
    static func url(reference: Bool) -> URL {
        let title = reference ? "Arrival details" : "Trip draft"
        let content = reference
            ? "<p>Check-in begins at 15:00. The entrance is on the garden side.</p><p>The station is a ten-minute walk away. Breakfast is served from 07:00 to 10:00.</p><button onclick=\"this.textContent='Copied to your plans'\">Try a live button</button>"
            : "<label for='draft'>Write a message, then Look at Arrival details.</label><textarea id='draft' placeholder='Our trip…'>I found a place near the station. </textarea>"
        let html = """
        <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>\(title)</title><style>
        :root{color-scheme:light dark;--ground:Canvas;--panel:Field;--ink:CanvasText;--secondary:GrayText;--accent:Highlight;--on-accent:HighlightText;font:20px/1.6 system-ui}
        body{margin:0;background:var(--ground);color:var(--ink)}main{max-width:650px;margin:15vh auto;padding:32px}
        h1{font-weight:500;letter-spacing:-.03em}p{margin:1.5em 0}small{color:var(--secondary)}label{display:block}
        textarea{box-sizing:border-box;width:100%;min-height:200px;margin-top:16px;padding:16px;background:var(--panel);color:var(--ink);font:inherit;border:1px solid var(--secondary);border-radius:12px}
        button{font:inherit;padding:10px 18px;background:var(--accent);color:var(--on-accent);border:0;border-radius:24px}
        </style><main><small>Refrax · Try with two pages</small><h1>\(title)</h1>\(content)
        <p><small>Hold Control to find these pages. Drag their titles to place them. Choose Look in a page's actions to visit it and return.</small></p></main></html>
        """
        return URL(string: "data:text/html;base64," + Data(html.utf8).base64EncodedString())!
    }
}
