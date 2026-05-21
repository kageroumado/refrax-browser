import SwiftUI

/// Renders markdown text content with code block support.
///
/// Parses markdown syntax and renders:
/// - Fenced code blocks (```language ... ```) with monospace font and background
/// - Inline code (`code`) with monospace font
/// - Bold (**text**) and italic (*text*)
/// - Regular text
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
        case codeBlock(code: String, language: String?)
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
                        let attributed = Self.parseInlineMarkdown(trimmed, isUserMessage: isUserMessage, colorScheme: colorScheme)
                        segments.append(.text(attributed))
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
                        let attributed = Self.parseInlineMarkdown(trimmed, isUserMessage: isUserMessage, colorScheme: colorScheme)
                        segments.append(.text(attributed))
                    }
                    break
                }
            }

            return segments.isEmpty ? [.text(AttributedString(text))] : segments
        }.value
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
