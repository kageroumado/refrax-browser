import SwiftUI

/// Shows a page's pending question over its own pane, blocking only that page.
struct PagePromptModifier: ViewModifier {
    let prompts: PagePrompts

    /// When false, the question stays pending but hidden (e.g. during layout mode).
    var isEnabled: Bool = true

    func body(content: Content) -> some View {
        content.overlay {
            if isEnabled, let pending = prompts.current {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(Layout.scrimOpacity))
                        .contentShape(.rect)
                        .onTapGesture {}
                    PagePromptCard(question: pending.question) { prompts.answer($0) }
                        .id(pending.id)
                }
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }

    private enum Layout {
        static let scrimOpacity = 0.18
    }
}

// MARK: - Card

private struct PagePromptCard: View {
    let question: PageQuestion
    let answer: (PageAnswer) -> Void

    @State private var text = ""
    @FocusState private var focus: Focus?

    private enum Focus: Hashable {
        case card
        case text
    }

    private enum Layout {
        static let width: CGFloat = 340
        static let padding: CGFloat = 20
        static let spacing: CGFloat = 14
        static let cornerRadius: CGFloat = 22
        static let iconSize: CGFloat = 40
        static let messageMaxHeight: CGFloat = 240
        static let stackedButtonWidth: CGFloat = 220
    }

    var body: some View {
        VStack(spacing: Layout.spacing) {
            header
            if case .prompt = question {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .text)
                    .onSubmit { answer(.text(text)) }
            }
            buttons
        }
        .padding(Layout.padding)
        .frame(width: Layout.width)
        .glassEffect(.regular, in: .rect(cornerRadius: Layout.cornerRadius))
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .card)
        .onKeyPress(.return) {
            answer(primaryAnswer)
            return .handled
        }
        .onExitCommand { answer(.decline) }
        .onAppear {
            if case let .prompt(_, defaultText, _) = question {
                text = defaultText ?? ""
                focus = .text
            } else {
                focus = .card
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        switch question {
        case let .alert(message, origin), let .confirm(message, origin), let .prompt(message, _, origin):
            titled(origin.isEmpty ? "This page says" : "\(origin) says", message: message)
        case let .leavePage(origin):
            titled("Leave this page?", message: "Changes you made on \(displayOrigin(origin)) may not be saved.")
        case let .permission(kind, origin):
            iconHeader(
                symbol: kind.symbolName,
                title: "“\(displayOrigin(origin))” would like to use your \(kind.requestedResource)",
                detail: kind.isRememberable ? "You can change this later in Site Settings." : nil,
            )
        case let .installExtension(name, store, _):
            iconHeader(
                symbol: "puzzlepiece.extension.fill",
                title: "Add “\(name)” to Refrax?",
                detail: "From \(store). It can read and change the sites its permissions cover.",
            )
        }
    }

    private func titled(_ title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ScrollView {
                Text(message)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Layout.messageMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconHeader(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: Layout.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        switch question {
        case .alert:
            HStack {
                Spacer()
                primaryButton("OK")
            }
        case .confirm, .prompt:
            HStack {
                Spacer()
                cancelButton("Cancel")
                primaryButton("OK")
            }
        case .leavePage:
            HStack {
                Spacer()
                cancelButton("Stay")
                primaryButton("Leave")
            }
        case let .permission(kind, _):
            VStack(spacing: 8) {
                primaryButton("Allow Once", fullWidth: true)
                if kind.isRememberable {
                    button("Always Allow", answer: .acceptAndRemember, fullWidth: true)
                        .buttonStyle(.glass)
                }
                cancelButton("Don’t Allow", fullWidth: true)
            }
            .frame(width: Layout.stackedButtonWidth)
            .controlSize(.large)
        case .installExtension:
            HStack {
                Spacer()
                cancelButton("Cancel")
                primaryButton("Add Extension")
            }
        }
    }

    private func button(_ title: String, answer value: PageAnswer, fullWidth: Bool) -> some View {
        Button { answer(value) } label: {
            Text(title).frame(maxWidth: fullWidth ? .infinity : nil)
        }
    }

    private func primaryButton(_ title: String, fullWidth: Bool = false) -> some View {
        button(title, answer: primaryAnswer, fullWidth: fullWidth)
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
    }

    private func cancelButton(_ title: String, fullWidth: Bool = false) -> some View {
        button(title, answer: .decline, fullWidth: fullWidth)
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
    }

    private var primaryAnswer: PageAnswer {
        if case .prompt = question { .text(text) } else { .accept }
    }

    private func displayOrigin(_ origin: String) -> String {
        origin.isEmpty ? "This page" : origin
    }
}
