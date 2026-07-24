import SwiftUI

/// Renders markdown release notes with proper block-level formatting.
///
/// SwiftUI's `Text(AttributedString(markdown:))` only supports inline markdown —
/// block-level elements like lists are collapsed into a single line. This view
/// parses the markdown into lines, detects bullet items, and renders them as
/// a proper bulleted list while preserving inline markdown formatting.
struct ReleaseNotesText: View {
    let markdown: String

    var body: some View {
        let lines = parseLines(markdown)

        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(inlineMarkdown(text))
                    }

                case .text(let text):
                    Text(inlineMarkdown(text))
                }
            }
        }
        .font(.system(size: Constants.Typography.bodySize))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Parsing

    private enum Line {
        case bullet(String)
        case text(String)
    }

    private func parseLines(_ markdown: String) -> [Line] {
        markdown
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    return Line.bullet(String(trimmed.dropFirst(2)))
                } else if trimmed.hasPrefix("* ") {
                    return Line.bullet(String(trimmed.dropFirst(2)))
                } else {
                    return Line.text(trimmed)
                }
            }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
