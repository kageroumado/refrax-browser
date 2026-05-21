import SwiftUI

/// Type of agent thought, determining the icon displayed.
enum ThoughtType: Sendable, Equatable {
    case scan
    case plan
    case read
    case act
    case question

    var icon: String {
        switch self {
        case .scan: "magnifyingglass"
        case .plan: "scope"
        case .read: "book"
        case .act: "bolt.fill"
        case .question: "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .scan: "Scanning"
        case .plan: "Planning"
        case .read: "Reading"
        case .act: "Acting"
        case .question: "Question"
        }
    }
}

/// A single thought entry in the agent's stream of consciousness.
struct ThoughtEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let type: ThoughtType
    let timestamp: Date
    /// Full text of the thought.
    var text: String
    /// Whether this thought is still being streamed (typewriter effect).
    var isStreaming: Bool

    init(type: ThoughtType, text: String, isStreaming: Bool = false) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.text = text
        self.isStreaming = isStreaming
    }

    /// First line of the thought for collapsed display.
    var firstLine: String {
        text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
    }

    /// Whether the thought has multiple lines (expandable).
    var isMultiline: Bool {
        text.contains("\n")
    }
}

/// Observable store for the thought stream.
///
/// Views read `thoughts` to display the stream. The action engine or
/// agent manager appends thoughts as the agent works.
///
/// ## Streaming Text
///
/// For the current streaming thought, use `updateStreamingText(_:)` which
/// updates the last thought's text without triggering per-character re-renders.
/// The view uses a timer-driven typewriter display for the streaming thought.
@Observable
@MainActor
final class ThoughtStreamStore {
    /// All thought entries, newest last.
    private(set) var thoughts: [ThoughtEntry] = []

    /// Maximum number of thoughts to retain.
    private let maxThoughts = 100

    /// Appends a new thought entry.
    func addThought(type: ThoughtType, text: String, isStreaming: Bool = false) {
        // Finalize any previously streaming thought
        if let lastIndex = thoughts.indices.last, thoughts[lastIndex].isStreaming {
            thoughts[lastIndex].isStreaming = false
        }

        let entry = ThoughtEntry(type: type, text: text, isStreaming: isStreaming)
        thoughts.append(entry)

        // Trim old thoughts
        if thoughts.count > maxThoughts {
            thoughts.removeFirst(thoughts.count - maxThoughts)
        }
    }

    /// Updates the text of the current streaming thought.
    ///
    /// This is the efficient path for streaming — instead of creating a new
    /// thought per token, we update the existing one. The view layer handles
    /// typewriter display independently.
    func updateStreamingText(_ text: String) {
        guard let lastIndex = thoughts.indices.last, thoughts[lastIndex].isStreaming else {
            return
        }
        thoughts[lastIndex].text = text
    }

    /// Finalizes the current streaming thought.
    func finalizeStreaming() {
        guard let lastIndex = thoughts.indices.last, thoughts[lastIndex].isStreaming else {
            return
        }
        thoughts[lastIndex].isStreaming = false
    }

    /// Clears all thoughts.
    func clear() {
        thoughts.removeAll()
    }
}

// MARK: - Thought Stream View

/// Displays the real-time stream of agent thinking.
///
/// Shows thought entries with type-based icons, auto-scrolls to the latest,
/// and supports expandable/collapsible entries for multi-line thoughts.
///
/// ## Typewriter Effect
///
/// The current streaming thought displays with a typewriter effect using
/// a timer that reveals characters in batches. This avoids per-character
/// re-renders — the timer updates a local `@State` character count, and
/// the view slices the string to that count.
struct AgentThoughtStream: View {
    @Environment(ThoughtStreamStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.thoughts) { thought in
                        ThoughtEntryView(thought: thought)
                            .id(thought.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("thought-bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: store.thoughts.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("thought-bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Thought Entry View

/// Renders a single thought entry with expand/collapse support.
private struct ThoughtEntryView: View {
    let thought: ThoughtEntry

    @State private var isExpanded: Bool = false

    /// Revealed character count for the typewriter effect.
    @State private var revealedCount: Int = 0

    /// Timer task for the typewriter.
    @State private var typewriterTask: Task<Void, Never>?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayText: String {
        if thought.isStreaming {
            // Show only revealed characters
            let endIndex = thought.text.index(
                thought.text.startIndex,
                offsetBy: min(revealedCount, thought.text.count),
            )
            return String(thought.text[..<endIndex])
        }
        return isExpanded || !thought.isMultiline ? thought.text : thought.firstLine
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Type icon
            Image(systemName: thought.type.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                // Thought text
                Text(displayText)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(isExpanded || thought.isStreaming ? nil : 1)
                    .textSelection(.enabled)

                // Expand/collapse for multiline non-streaming thoughts
                if !thought.isStreaming, thought.isMultiline {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Text(isExpanded ? "Less" : "More")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            thought.isStreaming
                ? Color.appAccentColor.opacity(0.05)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6),
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thought.type.label): \(thought.text)")
        .onAppear {
            if thought.isStreaming, !reduceMotion {
                startTypewriter()
            } else {
                revealedCount = thought.text.count
            }
        }
        .onDisappear {
            typewriterTask?.cancel()
        }
        .onChange(of: thought.isStreaming) { _, streaming in
            if !streaming {
                typewriterTask?.cancel()
                revealedCount = thought.text.count
            }
        }
        .onChange(of: thought.text.count) { _, newCount in
            // When streaming text grows, the typewriter will naturally catch up.
            // With reduce motion, always show full text immediately.
            if !thought.isStreaming || reduceMotion {
                revealedCount = newCount
            }
        }
    }

    private var iconColor: Color {
        switch thought.type {
        case .scan: .blue
        case .plan: .purple
        case .read: .green
        case .act: .orange
        case .question: Color(nsColor: .systemYellow)
        }
    }

    /// Starts the typewriter timer that reveals characters in batches.
    private func startTypewriter() {
        typewriterTask?.cancel()
        revealedCount = 0

        typewriterTask = Task { @MainActor in
            // Reveal characters in batches of 3 every 30ms
            // This gives a natural typing feel without per-character cost
            while !Task.isCancelled {
                let target = thought.text.count
                if revealedCount >= target {
                    // Caught up — wait for more text
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }

                // Reveal next batch
                revealedCount = min(revealedCount + 3, target)
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }
}

// MARK: - Preview

#Preview("Thought Stream") {
    let store = ThoughtStreamStore()

    AgentThoughtStream()
        .frame(width: 350, height: 400)
        .environment(store)
        .task {
            store.addThought(type: .scan, text: "Scanning page structure...\nFound: article with 12 sections, recipe format")
            try? await Task.sleep(for: .milliseconds(500))
            store.addThought(type: .plan, text: "This looks like a long-form recipe. The actual recipe is in section 13, but the technique explanations in sections 6-8 seem valuable.")
            try? await Task.sleep(for: .milliseconds(500))
            store.addThought(type: .plan, text: "Planning: scroll to \"Why This Recipe Works\" first")
            try? await Task.sleep(for: .milliseconds(300))
            store.addThought(type: .read, text: "Reading section on hydration ratios...", isStreaming: true)
            try? await Task.sleep(for: .seconds(1))
            store.updateStreamingText("Reading section on hydration ratios. This is interesting — they recommend 75% hydration for beginners, which is lower than most recipes.")
            try? await Task.sleep(for: .seconds(1))
            store.finalizeStreaming()
            store.addThought(type: .question, text: "Should I continue reading or jump to the recipe?")
        }
}

#Preview("Streaming Thought") {
    let store = ThoughtStreamStore()

    AgentThoughtStream()
        .frame(width: 350, height: 200)
        .environment(store)
        .task {
            store.addThought(type: .read, text: "", isStreaming: true)

            let fullText = "Analyzing the page content to find the most relevant information for your query about sourdough baking techniques."
            for i in 1 ... fullText.count {
                let index = fullText.index(fullText.startIndex, offsetBy: i)
                store.updateStreamingText(String(fullText[..<index]))
                try? await Task.sleep(for: .milliseconds(20))
            }
            store.finalizeStreaming()
        }
}
