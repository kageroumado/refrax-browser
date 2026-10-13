import SwiftUI

/// The page card's controls that appear only when the page asks for them: Save Password while
/// a login waits to be saved, and Translate while the page is in another language or
/// translated. They sit before Reload, in the card's control size, and each anchors its
/// popover to itself.
///
/// The container stays in the control row while both are hidden so it can follow the page's
/// language; it then takes back the row spacing it would otherwise add.
struct PageCardPromptControls: View {
    let page: WebPage?
    @Environment(AutoFillState.self) private var autoFillState
    @Environment(BrowserSettings.self) private var settings
    @Environment(TranslationManager.self) private var translationManager
    @State private var translation = PageTranslation()

    /// The card's control row: one square target per control, two points apart.
    enum Layout {
        static let controlSize: CGFloat = 30
        static let controlSpacing: CGFloat = 2
    }

    private var offersSavePassword: Bool {
        autoFillState.hasPendingSaveRequest && settings.autoFillMode == .builtIn
    }

    private var offersTranslate: Bool {
        page != nil && translation.isRelevant(targeting: translationManager.targetLanguage)
    }

    var body: some View {
        HStack(spacing: Layout.controlSpacing) {
            if offersSavePassword {
                PageCardSavePasswordControl()
            }
            if offersTranslate {
                PageCardTranslateControl(translation: translation)
            }
        }
        .padding(.trailing, offersSavePassword || offersTranslate ? 0 : -Layout.controlSpacing)
        .pageTranslation(translation, for: page)
    }
}

/// Save Password: opens the prompt by itself when a login is submitted, and again on click.
private struct PageCardSavePasswordControl: View {
    @State private var popoverController: SavePasswordPopoverController?

    var body: some View {
        Button {
            popoverController?.toggle()
        } label: {
            Image(systemName: "key")
                .frame(width: PageCardPromptControls.Layout.controlSize, height: PageCardPromptControls.Layout.controlSize)
                .contentShape(Rectangle())
        }
        .help("Save password")
        .accessibilityLabel("Save password")
        .focusEffectDisabled()
        .savePasswordPrompt(controller: $popoverController)
    }
}

/// Translate, or Show Original on a translated page; a spinner covers it while it translates.
private struct PageCardTranslateControl: View {
    let translation: PageTranslation
    @Environment(WindowState.self) private var windowState
    @State private var showsPopover = false

    private var title: String {
        translation.isTranslated ? "Show original page" : "Translate page"
    }

    var body: some View {
        Button {
            showsPopover = true
        } label: {
            ZStack {
                Image(systemName: "translate")
                    .if(translation.isTranslated) { $0.foregroundStyle(Color.appAccentColor) }
                    .opacity(translation.isTranslating ? 0 : 1)
                if translation.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: PageCardPromptControls.Layout.controlSize, height: PageCardPromptControls.Layout.controlSize)
            .contentShape(Rectangle())
        }
        .disabled(translation.isInProgress)
        .help(title)
        .accessibilityLabel(title)
        .focusEffectDisabled()
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            TranslationPopoverContent(translation: translation)
        }
        .onChange(of: showsPopover) { _, presented in
            windowState.controlIsland.tabInfo.isMenuPresented = presented
        }
    }
}

extension View {
    /// Opens the page card in the key window when a login waits to be saved, so the prompt
    /// appears beside the page without the pointer going to the card first.
    func pageCardOpensForPasswordSave() -> some View {
        modifier(PageCardPasswordSaveLatch())
    }
}

private struct PageCardPasswordSaveLatch: ViewModifier {
    @Environment(WindowState.self) private var windowState
    @Environment(AutoFillState.self) private var autoFillState
    @Environment(BrowserSettings.self) private var settings

    func body(content: Content) -> some View {
        content.onChange(of: autoFillState.hasPendingSaveRequest) { _, pending in
            guard pending, settings.autoFillMode == .builtIn, windowState.window?.isKeyWindow == true else { return }
            windowState.controlIsland.tabInfo.show()
        }
    }
}
