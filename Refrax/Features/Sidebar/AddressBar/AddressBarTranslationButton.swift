import SwiftUI

/// The address bar's Translate while the page is in a foreign language or translated; it opens
/// ``TranslationPopoverContent``.
struct AddressBarTranslationButton: View {
    /// The WebPage to translate.
    let webPage: WebPage?

    @Environment(TranslationManager.self) private var translationManager
    @State private var translation = PageTranslation()
    @State private var isHovered = false
    @State private var showsPopover = false

    private var shouldShow: Bool {
        translation.isRelevant(targeting: translationManager.targetLanguage)
    }

    private var foregroundColor: Color {
        if translation.isTranslated {
            return .appAccentColor
        }
        return isHovered ? .primary : .secondary
    }

    var body: some View {
        Button {
            guard !translation.isInProgress else { return }
            showsPopover = true
        } label: {
            ZStack {
                Image(systemName: "translate")
                    .font(.system(size: Constants.AddressBar.buttonFontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .frame(width: Constants.AddressBar.buttonWidth, height: Constants.AddressBar.buttonHeight)
                if translation.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("addressbar-translate")
        .accessibilityLabel(translation.isTranslated ? "View original page" : "Translate page")
        .disabled(translation.isInProgress)
        .opacity(shouldShow ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: shouldShow)
        .help(translation.isTranslated ? "View original page" : "Translate page")
        .if(showsPopover) { view in
            view.popover(isPresented: $showsPopover, arrowEdge: .bottom) {
                TranslationPopoverContent(translation: translation)
            }
        }
        .pageTranslation(translation, for: webPage)
    }
}
