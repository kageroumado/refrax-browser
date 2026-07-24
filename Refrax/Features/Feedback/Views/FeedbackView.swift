import SwiftUI

/// Main feedback composition form.
///
/// Presents contact information, category selection, subject, body,
/// file attachments, and a system info preview. Transitions to
/// ``FeedbackConfirmationView`` after submission.
struct FeedbackView: View {
    @Environment(FeedbackManager.self) private var manager
    @State private var showingSystemInfo = false

    var body: some View {
        if manager.didSubmitSuccessfully || manager.submissionError != nil && !manager.isSubmitting {
            FeedbackConfirmationView()
        } else {
            composeForm
        }
    }

    // MARK: - Compose Form

    private var composeForm: some View {
        @Bindable var manager = manager

        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    categoryPicker
                    subjectField
                    bodyEditor
                    contactFields
                    FeedbackAttachmentsView()
                }
                .padding(20)
            }

            Divider()

            footer
        }
    }

    // MARK: - Category

    private var categoryPicker: some View {
        @Bindable var manager = manager

        return HStack(spacing: 4) {
            ForEach(FeedbackCategory.allCases, id: \.self) { category in
                let isSelected = manager.category == category

                Button {
                    manager.category = category
                } label: {
                    Text(category.displayName)
                        .font(.system(size: Constants.Typography.bodySize, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            isSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
                            in: Capsule(),
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.fill.quaternary, in: Capsule())
    }

    // MARK: - Subject

    private var subjectField: some View {
        @Bindable var manager = manager

        return TextField("Subject", text: $manager.subject)
            .textFieldStyle(.plain)
            .font(.system(size: Constants.Typography.bodyMediumSize))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Body

    private var bodyEditor: some View {
        @Bindable var manager = manager

        return FeedbackTextEditor(
            text: $manager.body,
            placeholder: guidanceText,
            font: .systemFont(ofSize: Constants.Typography.bodyMediumSize),
        )
        .frame(minHeight: 140)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var guidanceText: String {
        switch manager.category {
        case .bug:
            "Describe the issue. Include:\n- Steps to reproduce\n- URL of the affected page (if applicable)\n- What you expected vs. what happened\n- Attach a screenshot if possible\n\nPlease verify you're on the latest version."
        case .feature:
            "Describe the feature you'd like to see.\n\nWhat problem would it solve? How would you expect it to work?"
        case .general:
            "Share your thoughts, suggestions, or questions.\n\nIf you're experiencing performance issues, check that your Mac is connected to power and not thermally throttled (Activity Monitor > CPU)."
        case .crash:
            "Describe what you were doing when the crash occurred.\n\n- Steps to reproduce\n- URL of the page you were viewing\n- Does it happen every time?\n\nLog files are attached automatically."
        }
    }

    // MARK: - Contact

    private var contactFields: some View {
        @Bindable var manager = manager

        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Name (optional)", text: $manager.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: Constants.Typography.bodyMediumSize))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 6) {
                Image(systemName: "envelope")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Email (optional)", text: $manager.email)
                    .textFieldStyle(.plain)
                    .font(.system(size: Constants.Typography.bodyMediumSize))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            systemInfoLink

            Spacer()

            if manager.isSubmitting {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await manager.submit() }
            } label: {
                Text("Send")
                    .font(.system(size: Constants.Typography.bodySize, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 7)
                    .background(Color.appAccentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(manager.isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var systemInfoLink: some View {
        Button {
            showingSystemInfo.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text("System info included")
            }
            .font(.system(size: Constants.Typography.captionSize))
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingSystemInfo) {
            systemInfoPopover
        }
    }

    @ViewBuilder
    private var systemInfoPopover: some View {
        if let info = manager.systemInfo {
            VStack(alignment: .leading, spacing: 8) {
                Text("System Information")
                    .font(.system(size: Constants.Typography.bodyMediumSize, weight: .medium))

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    infoRow("Refrax", "\(info.refraxVersion) (\(info.refraxBuild))")
                    infoRow("macOS", info.macOSVersion)
                    infoRow("Hardware", info.hardwareModel)
                    infoRow("Memory", "\(info.memoryGB) GB")
                    infoRow("Locale", info.locale)
                    infoRow("Tabs", "\(info.tabCount)")
                    infoRow("Spaces", "\(info.spaceCount)")
                    infoRow("Extensions", "\(info.extensionCount)")
                }
                .font(.system(size: Constants.Typography.captionSize))
            }
            .padding(12)
            .frame(width: 260)
        } else {
            ProgressView("Collecting...")
                .padding()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.tertiary)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Text Editor with Placeholder

/// NSTextView-backed text editor with controlled insets and placeholder support.
///
/// SwiftUI's `TextEditor` has uncontrollable internal NSTextView padding that makes
/// placeholder overlay alignment impossible. This wraps NSTextView directly to set
/// `textContainerInset` and `lineFragmentPadding` explicitly.
///
/// The placeholder is drawn as an attributed string in a sibling text view that shares
/// the same text container insets, guaranteeing perfect alignment.
private struct FeedbackTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont

    private static let inset = NSSize(width: 12, height: 8)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = Self.inset
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.placeholderString = placeholder
        textView.placeholderFont = font
        textView.placeholderColor = .placeholderTextColor

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.placeholderString = placeholder
        textView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

/// NSTextView subclass that draws placeholder text when empty.
private final class PlaceholderTextView: NSTextView {
    var placeholderString: String = ""
    var placeholderFont: NSFont = .systemFont(ofSize: 13)
    var placeholderColor: NSColor = .placeholderTextColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholderString.isEmpty else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: placeholderFont,
            .foregroundColor: placeholderColor,
        ]
        let attrString = NSAttributedString(string: placeholderString, attributes: attrs)

        // Draw at the same position the text container renders text
        let inset = textContainerInset
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: inset.width + padding, y: inset.height)

        let drawRect = NSRect(
            origin: origin,
            size: NSSize(
                width: bounds.width - (inset.width + padding) * 2,
                height: bounds.height - inset.height * 2,
            ),
        )
        attrString.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
