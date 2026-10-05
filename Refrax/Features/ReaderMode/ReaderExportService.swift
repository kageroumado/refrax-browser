import AppKit
import Foundation
import UniformTypeIdentifiers

/// Service for exporting reader mode content to various formats.
///
/// Supports:
/// - Markdown export for note-taking and archival
/// - Share Sheet integration for Apple Notes and other apps
/// - Plain text fallback for universal compatibility
///
/// ## Usage
///
/// ```swift
/// let service = ReaderExportService(article: article)
///
/// // Convert off the main actor
/// let markdown = await service.markdown()
///
/// // Share to Notes
/// let items = service.createShareItems()
/// NSSharingServicePicker(items: items).show(...)
/// ```
nonisolated struct ReaderExportService: Sendable {
    let article: ExtractedArticle

    // MARK: - Markdown Export

    /// The article as Markdown, converted on the concurrent pool.
    ///
    /// Conversion runs a regular expression pass per tag over the whole
    /// article, which takes long enough on a large page to stall the UI.
    @concurrent
    func markdown() async -> String {
        exportAsMarkdown()
    }

    /// Writes the article as Markdown to `url`, converting and writing on the
    /// concurrent pool.
    @concurrent
    func writeMarkdown(to url: URL) async throws {
        try exportAsMarkdown().write(to: url, atomically: true, encoding: .utf8)
    }

    /// Exports the article as a Markdown string.
    ///
    /// Includes:
    /// - Title as H1
    /// - Source URL, author, and date in a blockquote header
    /// - Full article content converted from HTML to Markdown
    private func exportAsMarkdown() -> String {
        var md = "# \(article.title)\n\n"

        // Build metadata block
        var metaLines: [String] = []
        metaLines.append("Source: [\(article.sourceURL.host ?? "Link")](\(article.sourceURL.absoluteString))")

        if let author = article.byline {
            metaLines.append("Author: \(author)")
        }

        if let date = article.publishedTime {
            metaLines.append("Published: \(date.formatted(date: .long, time: .omitted))")
        }

        if let siteName = article.siteName {
            metaLines.append("Site: \(siteName)")
        }

        // Add metadata as blockquote
        for line in metaLines {
            md += "> \(line)\n"
        }

        md += "\n---\n\n"
        md += htmlToMarkdown(article.content)

        return md
    }

    /// Suggested filename for the markdown export.
    var suggestedFilename: String {
        let sanitized = article.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "\"", with: "'")
            .prefix(100)

        return "\(sanitized).md"
    }

    // MARK: - Share Items

    /// Creates share items for the Share Sheet.
    ///
    /// Returns an array containing:
    /// - Attributed string (rich text for Notes)
    /// - Plain text fallback
    /// - Source URL
    ///
    /// Runs on the main actor: the rich text comes from `NSAttributedString`'s
    /// HTML importer, which WebKit requires on the main thread.
    @MainActor
    func createShareItems() -> [Any] {
        var items: [Any] = []

        // Rich text for Notes (preserves formatting)
        if let attributedString = htmlToAttributedString(article.content) {
            // Prepend title and byline
            let fullContent = NSMutableAttributedString()

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            ]
            fullContent.append(NSAttributedString(string: article.title + "\n\n", attributes: titleAttrs))

            // Byline
            if let byline = article.byline {
                let bylineAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                fullContent.append(NSAttributedString(string: byline + "\n\n", attributes: bylineAttrs))
            }

            // Content
            fullContent.append(attributedString)

            // Source link
            let sourceAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            fullContent.append(NSAttributedString(string: "\n\nSource: \(article.sourceURL.absoluteString)", attributes: sourceAttrs))

            items.append(fullContent)
        }

        // Plain text fallback
        let plainText = """
        \(article.title)
        
        \(article.byline ?? "")
        
        \(article.textContent)
        
        Source: \(article.sourceURL.absoluteString)
        """
        items.append(plainText)

        // URL for some share targets
        items.append(article.sourceURL)

        return items
    }

    // MARK: - Save Panel

    /// Presents a save panel and saves the markdown export.
    ///
    /// - Parameter window: The parent window for the save panel.
    @MainActor
    func saveAsMarkdown(from window: NSWindow?) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.title = "Save Article as Markdown"

        let response: NSApplication.ModalResponse = if let window {
            await panel.beginSheetModal(for: window)
        } else {
            await panel.begin()
        }

        guard response == .OK, let url = panel.url else { return }

        do {
            try await writeMarkdown(to: url)
        } catch {
            Logger.error("Failed to save markdown: \(error)", category: Logger.tabs)
        }
    }

    // MARK: - HTML to Markdown Conversion

    private func htmlToMarkdown(_ html: String) -> String {
        var result = html

        // Remove scripts and styles (use NSRegularExpression for multiline matching)
        result = removeHTMLBlockTag(from: result, tag: "script")
        result = removeHTMLBlockTag(from: result, tag: "style")

        // Headers
        result = replaceHTMLTag(in: result, tag: "h1", with: { "# \($0)\n\n" })
        result = replaceHTMLTag(in: result, tag: "h2", with: { "## \($0)\n\n" })
        result = replaceHTMLTag(in: result, tag: "h3", with: { "### \($0)\n\n" })
        result = replaceHTMLTag(in: result, tag: "h4", with: { "#### \($0)\n\n" })
        result = replaceHTMLTag(in: result, tag: "h5", with: { "##### \($0)\n\n" })
        result = replaceHTMLTag(in: result, tag: "h6", with: { "###### \($0)\n\n" })

        // Paragraphs
        result = replaceHTMLTag(in: result, tag: "p", with: { "\($0)\n\n" })

        // Bold and italic
        result = replaceHTMLTag(in: result, tag: "strong", with: { "**\($0)**" })
        result = replaceHTMLTag(in: result, tag: "b", with: { "**\($0)**" })
        result = replaceHTMLTag(in: result, tag: "em", with: { "*\($0)*" })
        result = replaceHTMLTag(in: result, tag: "i", with: { "*\($0)*" })

        // Code
        result = replaceHTMLTag(in: result, tag: "code", with: { "`\($0)`" })
        result = replaceHTMLTag(in: result, tag: "pre", with: { "```\n\($0)\n```\n\n" })

        // Links
        result = result.replacingOccurrences(
            of: "<a[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>",
            with: "[$2]($1)",
            options: [.regularExpression, .caseInsensitive],
        )

        // Images
        result = result.replacingOccurrences(
            of: "<img[^>]*src=\"([^\"]*)\"[^>]*alt=\"([^\"]*)\"[^>]*/?>",
            with: "![$2]($1)\n\n",
            options: [.regularExpression, .caseInsensitive],
        )
        result = result.replacingOccurrences(
            of: "<img[^>]*src=\"([^\"]*)\"[^>]*/?>",
            with: "![]($1)\n\n",
            options: [.regularExpression, .caseInsensitive],
        )

        // Blockquotes
        result = result.replacingOccurrences(
            of: "<blockquote[^>]*>(.*?)</blockquote>",
            with: { match in
                let content = match.replacingOccurrences(of: "<blockquote[^>]*>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "</blockquote>", with: "", options: .caseInsensitive)
                let lines = content.split(separator: "\n")
                return lines.map { "> \($0)" }.joined(separator: "\n") + "\n\n"
            },
        )

        // Lists
        result = convertLists(result)

        // Line breaks
        result = result.replacingOccurrences(of: "<br[^>]*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])

        // Horizontal rules
        result = result.replacingOccurrences(of: "<hr[^>]*/?>", with: "\n---\n\n", options: [.regularExpression, .caseInsensitive])

        // Remove remaining HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        result = decodeHTMLEntities(result)

        // Clean up whitespace
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Removes a block-level HTML tag and its contents (handles multiline).
    private func removeHTMLBlockTag(from string: String, tag: String) -> String {
        let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return string
        }

        return regex.stringByReplacingMatches(
            in: string,
            range: NSRange(string.startIndex..., in: string),
            withTemplate: "",
        )
    }

    /// Replaces HTML tags with transformed content (handles multiline).
    private func replaceHTMLTag(in string: String, tag: String, with replacement: (String) -> String) -> String {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return string
        }

        return string.replacingMatches(of: regex) { match, source in
            let contentRange = match.range(at: 1)
            guard contentRange.location != NSNotFound else { return nil }
            return replacement(source.substring(with: contentRange))
        }
    }

    private func convertLists(_ html: String) -> String {
        var result = html

        // Unordered lists
        result = replaceHTMLTag(in: result, tag: "ul") { content in
            convertListItems(content, ordered: false) + "\n"
        }

        // Ordered lists
        result = replaceHTMLTag(in: result, tag: "ol") { content in
            convertListItems(content, ordered: true) + "\n"
        }

        return result
    }

    private func convertListItems(_ html: String, ordered: Bool) -> String {
        let pattern = "<li[^>]*>(.*?)</li>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return html
        }

        var items: [String] = []
        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))

        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges >= 2 else { continue }
            let contentRange = match.range(at: 1)
            guard contentRange.location != NSNotFound else { continue }

            var content = nsString.substring(with: contentRange)
            content = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)

            let prefix = ordered ? "\(index + 1). " : "- "
            items.append(prefix + content)
        }

        return items.joined(separator: "\n")
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string

        // `&amp;` is decoded last, so an escaped entity such as `&amp;lt;`
        // decodes once, to `&lt;`.
        let entities: KeyValuePairs<String, String> = [
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&nbsp;": " ",
            "&ndash;": "\u{2013}",
            "&mdash;": "\u{2014}",
            "&lsquo;": "\u{2018}",
            "&rsquo;": "\u{2019}",
            "&ldquo;": "\u{201C}",
            "&rdquo;": "\u{201D}",
            "&hellip;": "\u{2026}",
            "&copy;": "\u{00A9}",
            "&reg;": "\u{00AE}",
            "&trade;": "\u{2122}",
        ]

        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        // Numeric entities
        let numericPattern = "&#([0-9]+);"
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            result = result.replacingMatches(of: regex) { match, source in
                let codeRange = match.range(at: 1)
                guard codeRange.location != NSNotFound,
                      let code = Int(source.substring(with: codeRange)),
                      let scalar = Unicode.Scalar(code)
                else { return nil }
                return String(Character(scalar))
            }
        }

        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - HTML to Attributed String

    private func htmlToAttributedString(_ html: String) -> NSAttributedString? {
        // Wrap content in proper HTML structure for better parsing
        let wrappedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 14px; }
            </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """

        guard let data = wrappedHTML.data(using: .utf8) else { return nil }

        return try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil,
        )
    }
}

// MARK: - String Extension for Block Replacement

private nonisolated extension String {
    func replacingOccurrences(of pattern: String, with replacement: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return self
        }
        return replacingMatches(of: regex) { match, source in
            replacement(source.substring(with: match.range))
        }
    }

    /// Replaces each match of `regex` with what `replacement` returns for it,
    /// leaving a match unchanged when it returns `nil`.
    ///
    /// Works on `NSString` throughout, so the UTF-16 ranges the regular
    /// expression reports index the text they came from. Matches are replaced
    /// last to first, which keeps the earlier ranges valid.
    func replacingMatches(
        of regex: NSRegularExpression,
        with replacement: (NSTextCheckingResult, NSString) -> String?,
    ) -> String {
        let source = self as NSString
        let result = NSMutableString(string: source)
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() where match.range.location != NSNotFound {
            if let text = replacement(match, source) {
                result.replaceCharacters(in: match.range, with: text)
            }
        }
        return result as String
    }
}
