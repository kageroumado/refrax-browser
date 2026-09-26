import SwiftUI

/// Renders markdown text content with code block support.
///
/// Parses markdown syntax and renders:
/// - Fenced code blocks (```language ... ```) with monospace font and background
/// - Headings (`#` through `######`)
/// - Bulleted (`-`, `*`, `+`) and numbered (`1.`, `1)`) lists, nested by indentation
/// - Inline code (`code`) with monospace font
/// - Bold (**text**) and italic (*text*)
/// - Paragraphs separated by blank lines
struct MarkdownContentView: View {
    let content: String
    let isUserMessage: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// Cached parsed segments to avoid re-parsing on every render.
    @State private var parsedSegments: [ContentSegment]?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .text(attributed):
                    Text(attributed)
                        .textSelection(.enabled)

                case let .heading(attributed):
                    Text(attributed)
                        .textSelection(.enabled)
                        .padding(.top, 2)

                case let .list(items):
                    listView(items)

                case let .codeBlock(code, language):
                    codeBlockView(code: code, language: language)
                }
            }
        }
        .task(id: content) {
            // Parse on a detached task to avoid blocking main thread
            let parsed = await parseContent(content)
            parsedSegments = parsed
        }
    }

    private var segments: [ContentSegment] {
        parsedSegments ?? [.text(AttributedString(content))]
    }

    // MARK: - Content Segment

    private enum ContentSegment {
        case text(AttributedString)
        case heading(AttributedString)
        case list([ListItem])
        case codeBlock(code: String, language: String?)
    }

    /// One list line: its marker (`•` or the number as written), nesting depth, and text.
    private nonisolated struct ListItem: Sendable {
        let marker: String
        let depth: Int
        let text: AttributedString
    }

    // MARK: - Parsing

    /// Parses content into segments (runs on background thread).
    private func parseContent(_ text: String) async -> [ContentSegment] {
        await Task.detached(priority: .userInitiated) { [isUserMessage, colorScheme] in
            var segments: [ContentSegment] = []
            var remaining = text

            // Regex pattern for fenced code blocks: ```language\ncode\n```
            let pattern = #"```(\w*)\n?([\s\S]*?)```"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return [.text(Self.parseInlineMarkdown(text, isUserMessage: isUserMessage, colorScheme: colorScheme))]
            }

            while !remaining.isEmpty {
                let range = NSRange(remaining.startIndex..., in: remaining)
                if let match = regex.firstMatch(in: remaining, options: [], range: range) {
                    // Get the text before the code block
                    let beforeRange = Range(NSRange(location: 0, length: match.range.location), in: remaining)!
                    let beforeText = String(remaining[beforeRange])
                    if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let trimmed = beforeText.trimmingCharacters(in: .newlines)
                        segments += Self.parseBlocks(trimmed, isUserMessage: isUserMessage, colorScheme: colorScheme)
                    }

                    // Extract language and code
                    let languageRange = Range(match.range(at: 1), in: remaining)!
                    let codeRange = Range(match.range(at: 2), in: remaining)!
                    let language = String(remaining[languageRange])
                    let code = String(remaining[codeRange]).trimmingCharacters(in: .newlines)

                    segments.append(.codeBlock(code: code, language: language.isEmpty ? nil : language))

                    // Move past this match
                    let afterStart = remaining.index(remaining.startIndex, offsetBy: match.range.location + match.range.length)
                    remaining = String(remaining[afterStart...])
                } else {
                    // No more code blocks, append remaining text
                    let trimmed = remaining.trimmingCharacters(in: .newlines)
                    if !trimmed.isEmpty {
                        segments += Self.parseBlocks(trimmed, isUserMessage: isUserMessage, colorScheme: colorScheme)
                    }
                    break
                }
            }

            return segments.isEmpty ? [.text(AttributedString(text))] : segments
        }.value
    }

    /// Splits text outside code blocks into paragraphs, headings, and lists.
    private nonisolated static func parseBlocks(
        _ text: String,
        isUserMessage: Bool,
        colorScheme: ColorScheme,
    ) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var paragraph: [String] = []
        var listItems: [ListItem] = []

        func inline(_ text: String) -> AttributedString {
            parseInlineMarkdown(text, isUserMessage: isUserMessage, colorScheme: colorScheme)
        }
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            segments.append(.text(inline(paragraph.joined(separator: "\n"))))
            paragraph.removeAll()
        }
        func flushList() {
            guard !listItems.isEmpty else { return }
            segments.append(.list(listItems))
            listItems.removeAll()
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                flushList()
            } else if let match = line.wholeMatch(of: /(#{1,6})\s+(.+)/) {
                flushParagraph()
                flushList()
                var heading = inline(String(match.2))
                heading.font = match.1.count == 1 ? .title3.bold() : .headline
                segments.append(.heading(heading))
            } else if let match = line.wholeMatch(of: /( *)([-*+]|\d{1,9}[.)])\s+(.*)/) {
                flushParagraph()
                let marker = String(match.2)
                listItems.append(ListItem(
                    marker: marker.first?.isNumber == true ? marker : "•",
                    depth: match.1.count / 2,
                    text: inline(String(match.3)),
                ))
            } else if !listItems.isEmpty, line.first == " " {
                // An indented continuation line belongs to the list item above it.
                let last = listItems.removeLast()
                listItems.append(ListItem(
                    marker: last.marker,
                    depth: last.depth,
                    text: last.text + AttributedString(" ") + inline(line.trimmingCharacters(in: .whitespaces)),
                ))
            } else {
                flushList()
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushList()
        return segments
    }

    /// Parses inline markdown (bold, italic, inline code) into AttributedString.
    /// Nonisolated to allow calling from detached task.
    private nonisolated static func parseInlineMarkdown(
        _ text: String,
        isUserMessage: Bool,
        colorScheme: ColorScheme,
    ) -> AttributedString {
        var result = AttributedString()
        var remaining = text[...]

        let inlineCodeBackground = isUserMessage
            ? Color.white.opacity(0.15)
            : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))

        while !remaining.isEmpty {
            // Check for inline code: `code`
            if remaining.hasPrefix("`"), let endIndex = remaining.dropFirst().firstIndex(of: "`") {
                let codeStart = remaining.index(after: remaining.startIndex)
                let code = String(remaining[codeStart ..< endIndex])

                var attr = AttributedString(code)
                attr.font = .system(.body, design: .monospaced)
                attr.backgroundColor = inlineCodeBackground
                result += attr

                remaining = remaining[remaining.index(after: endIndex)...]
                continue
            }

            // Check for bold: **text**
            if remaining.hasPrefix("**") {
                let searchRange = remaining.dropFirst(2)
                if let endRange = searchRange.range(of: "**") {
                    let boldText = String(searchRange[..<endRange.lowerBound])
                    var attr = AttributedString(boldText)
                    attr.font = .body.bold()
                    result += attr

                    remaining = searchRange[endRange.upperBound...]
                    continue
                }
            }

            // Check for italic: *text* (but not **)
            if remaining.hasPrefix("*"), !remaining.hasPrefix("**") {
                let searchRange = remaining.dropFirst()
                if let endIndex = searchRange.firstIndex(of: "*") {
                    let italicText = String(searchRange[..<endIndex])
                    var attr = AttributedString(italicText)
                    attr.font = .body.italic()
                    result += attr

                    remaining = searchRange[searchRange.index(after: endIndex)...]
                    continue
                }
            }

            // Regular character
            var char = AttributedString(String(remaining.first!))
            char.font = .body
            result += char
            remaining = remaining.dropFirst()
        }

        return result
    }

    // MARK: - List View

    private func listView(_ items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: Layout.listItemSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.marker)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(item.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, CGFloat(item.depth) * Layout.listIndent)
            }
        }
    }

    private enum Layout {
        static let listItemSpacing: CGFloat = 4
        static let listIndent: CGFloat = 16
    }

    // MARK: - Code Block View

    private func codeBlockView(code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label (if present)
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }

            // Code content
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, language == nil ? 8 : 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(codeBlockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var codeBlockBackground: Color {
        if isUserMessage {
            Color.white.opacity(0.12)
        } else {
            colorScheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.04)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        // Assistant message with code
        MarkdownContentView(
            content: """
            Here's how to do it:
            
            ```swift
            let greeting = "Hello, World!"
            print(greeting)
            ```
            
            You can also use `inline code` like this.

            ## Steps
            - First item
            - Second item
              - Nested item
            1. Numbered
            2. Also numbered
            
            **Bold text** and *italic text* work too.
            """,
            isUserMessage: false,
        )
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)

        // User message
        MarkdownContentView(
            content: "Can you show me how to use `async/await`?",
            isUserMessage: true,
        )
        .padding()
        .background(Color.blue)
        .foregroundStyle(.white)
        .cornerRadius(12)
    }
    .padding()
}
