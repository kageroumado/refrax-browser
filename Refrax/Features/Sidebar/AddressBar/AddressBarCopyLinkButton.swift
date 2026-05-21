import SwiftUI

/// Button to copy the current page URL to the clipboard.
///
/// Appears on hover in the address bar, providing quick access
/// to copy the URL with tracking parameters removed.
///
/// Hold Option to copy as a Markdown link: `[Title](URL)`
struct AddressBarCopyLinkButton: View {
    @Environment(ModifierKeysState.self) private var modifierKeys

    let copyURL: () -> Void
    let copyMarkdown: () -> Void

    @State private var isHovered = false
    @State private var showsCopiedFeedback = false

    private var isMarkdownMode: Bool {
        modifierKeys.isOptionPressed
    }

    var body: some View {
        Button {
            if isMarkdownMode {
                copyMarkdown()
            } else {
                copyURL()
            }
            showCopiedFeedback()
        } label: {
            Image(systemName: showsCopiedFeedback ? "checkmark" : (isMarkdownMode ? "doc.text" : "link"))
                .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                .foregroundStyle(showsCopiedFeedback ? .green : (isHovered ? .primary : .secondary))
                .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("addressbar-copy-link")
        .accessibilityLabel(isMarkdownMode ? "Copy as Markdown link" : "Copy link")
        .help(isMarkdownMode ? "Copy as Markdown link" : "Copy link")
        .animation(.easeInOut(duration: 0.15), value: showsCopiedFeedback)
        .animation(.easeInOut(duration: 0.1), value: isMarkdownMode)
    }

    private func showCopiedFeedback() {
        showsCopiedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showsCopiedFeedback = false
        }
    }
}
