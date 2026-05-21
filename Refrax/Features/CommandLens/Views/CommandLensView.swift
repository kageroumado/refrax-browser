import AppKit
import SwiftUI

struct CommandLensView: View {
    @Environment(CommandLensManager.self) private var manager
    @Environment(WindowState.self) private var windowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.commandLensIsSmall) private var isSmallMode

    @Namespace private var glassNamespace

    @State private var providerSwitchScale: CGFloat = 1.0
    @State private var shouldSelectAll = false
    @State private var autoShowButtonsTask: Task<Void, Never>?

    private enum Layout {
        static let height: CGFloat = 52
        static let heightSmall: CGFloat = 32 // Match address bar height
        static let cornerRadius: CGFloat = 26
        static let cornerRadiusSmall: CGFloat = 16 // Half of heightSmall
        static let buttonSpacing: CGFloat = 8
        static let containerSpacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 16
        static let suggestionInset: CGFloat = 8
        /// Inner corner radius for concentric effect: outer - inset
        static var suggestionCornerRadius: CGFloat {
            cornerRadius - suggestionInset
        }
    }

    // MARK: - Body

    var body: some View {
        GlassEffectContainer(spacing: Layout.containerSpacing) {
            HStack(spacing: Layout.buttonSpacing) {
                VStack(spacing: 0) {
                    textFieldCapsule
                    aiResponseArea
                    suggestionsArea
                }
                .scaleEffect(providerSwitchScale)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: currentCornerRadius))
                .glassEffectID("textField", in: glassNamespace)
                .overlay {
                    RoundedRectangle(cornerRadius: currentCornerRadius)
                        .stroke(.secondary.opacity(0.7), lineWidth: 1)
                        .shadow(color: .secondary.opacity(0.25), radius: 3, x: 0, y: 1)
                        .shadow(color: .secondary.opacity(0.15), radius: 2, x: 0, y: 0)
                }

                if showCategoryButtons {
                    categoryButtonsRow
                }
            }
            .animation(reduceMotion ? nil : .default, value: showCategoryButtons)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3), value: providerSwitchScale)
        .animation(reduceMotion ? nil : .spring(duration: 0.5), value: hasSuggestions)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: manager.showSearchEngineBadge)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: windowState.isCreatingReferenceTab)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: windowState.layoutModeTargetPosition)
        .task { onAppear() }
        .onChange(of: manager.inputText) { _, newValue in
            if !newValue.isEmpty { cancelAutoShowButtonsTimer() }
        }
        .onDisappear {
            cancelAutoShowButtonsTimer()
            manager.reset()
        }
    }

    // MARK: - Search Bar Area

    // Main search bar with glass container for morphing effects.
//    private var searchBarArea: some View {
//
//    }

    /// Whether to show category buttons (only in normal mode).
    private var showCategoryButtons: Bool {
        !isSmallMode && manager.showCategoryButtons
    }

    /// Corner radius based on mode.
    private var currentCornerRadius: CGFloat {
        isSmallMode ? Layout.cornerRadiusSmall : Layout.cornerRadius
    }

    // MARK: - Text Field Capsule

    /// The main text input capsule.
    private var textFieldCapsule: some View {
        HStack(spacing: isSmallMode ? 8 : 12) {
            searchIcon
            referenceTabIndicator
            layoutModeIndicator
            searchEngineBadge
            textField
            loadingIndicator
            aiIntentIndicator
            clearButton
        }
        .frame(height: isSmallMode ? Layout.heightSmall : Layout.height)
        .padding(.horizontal, isSmallMode ? 8 : 16)
    }

    @ViewBuilder
    private var aiIntentIndicator: some View {
        if manager.isAIIntent, !manager.isAIMode, !showCategoryButtons {
            Button { manager.sendAIQuery() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                    Text("⌘↵")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.purple.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Ask Claude (⌘Enter)")
        }
    }

    private var searchIcon: some View {
        Image(systemName: searchIconName)
            .font(isSmallMode ? .system(size: 14, weight: .medium) : .system(size: 22, weight: .medium))
            .foregroundStyle(manager.categorySearchMode != nil ? .primary : .secondary)
            .contentTransition(.symbolEffect(.replace))
    }

    private var searchIconName: String {
        guard let mode = manager.categorySearchMode else {
            return "sparkle.magnifyingglass"
        }
        switch mode {
        case .history:
            return "clock.arrow.circlepath"
        case .bookmarks:
            return "bookmark"
        case .downloads:
            return "arrow.down.circle"
        case .settings:
            return "gear"
        }
    }

    @ViewBuilder
    private var searchEngineBadge: some View {
        if manager.showSearchEngineBadge {
            SearchEngineBadge(engine: manager.currentSearchEngine)
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// Shows a badge when the command lens is creating a reference tab.
    @ViewBuilder
    private var referenceTabIndicator: some View {
        if windowState.isCreatingReferenceTab {
            contextBadge(icon: "sidebar.right", color: .teal)
        }
    }

    /// Shows a badge when the command lens is creating a tab in a layout pane.
    @ViewBuilder
    private var layoutModeIndicator: some View {
        if windowState.layoutModeTargetPosition != nil {
            contextBadge(icon: "rectangle.split.2x1", color: .blue)
        }
    }

    /// Reusable context badge for reference/layout mode indicators.
    private func contextBadge(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .transition(.scale.combined(with: .opacity))
    }

    private var textField: some View {
        CommandLensTextField(
            text: Bindable(manager).inputText,
            placeholder: textFieldPlaceholder,
            fontSize: isSmallMode ? Constants.Typography.bodyMediumSize : 26,
            inlineCompletion: manager.inlineCompletion,
            inlineCompletionRange: manager.inlineCompletionRange,
            selectAll: $shouldSelectAll,
            onTextChange: { manager.onInputChanged($0) },
            onCommit: { commandKey, optionKey in handleCommit(commandKey: commandKey, optionKey: optionKey) },
            onTab: { handleTabKey() },
            onEscape: { handleEscape() },
            onUpArrow: { manager.moveSelection(by: -1) },
            onDownArrow: { manager.moveSelection(by: 1) },
            onLeftArrow: { handleLeftArrow() },
            onRightArrow: { handleRightArrow() },
            onDelete: { handleDelete() },
            onAcceptCompletion: { manager.acceptInlineCompletion() },
            onRejectCompletion: { manager.rejectInlineCompletion() },
        )
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if manager.isLoading {
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var clearButton: some View {
        if !manager.inputText.isEmpty, !showCategoryButtons {
            Button { manager.reset() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: isSmallMode ? 12 : 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var textFieldPlaceholder: String {
        // Category search mode
        if let mode = manager.categorySearchMode {
            switch mode {
            case .history:
                return "Search history..."
            case .bookmarks:
                return "Search bookmarks..."
            case .downloads:
                return "Search downloads..."
            case .settings:
                return "Search settings..."
            }
        }
        if manager.hasCategorySelection, let button = manager.expandedModeButtons[safe: manager.expandedSelection] {
            return button.label
        }
        if manager.showSearchEngineBadge {
            return "Search \(manager.currentSearchEngine.name)"
        }
        return "Ask, search, or go..."
    }

    // MARK: - Category Buttons

    /// Row of category buttons with individual glass effects.
    private var categoryButtonsRow: some View {
        ForEach(Array(manager.expandedModeButtons.enumerated()), id: \.element.id) { index, button in
            CategoryButton(
                button: button,
                isSelected: index == manager.expandedSelection,
                index: index,
                height: Layout.height,
                namespace: glassNamespace,
            )
        }
    }

    // MARK: - AI Response Area

    @ViewBuilder
    private var aiResponseArea: some View {
        if manager.isAIMode {
            Divider().padding(.horizontal, 12)
            ScrollView {
                CommandLensAIView()
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - Suggestions Area

    @ViewBuilder
    private var suggestionsArea: some View {
        if manager.isPopupVisible, !manager.suggestions.isEmpty, !manager.isAIMode {
            VStack(spacing: 0) {
                Divider().padding(.horizontal, Layout.horizontalPadding)
                SuggestionsListView()
            }
            .clipped()
        }
    }

    private var hasSuggestions: Bool {
        manager.isPopupVisible && !manager.suggestions.isEmpty
    }

    // MARK: - Lifecycle

    private func onAppear() {
        if isSmallMode {
            manager.inputText = windowState.focusedPage?.url.absoluteString ?? ""
            shouldSelectAll = true
        } else {
            startAutoShowButtonsTimer()
        }
    }

    // MARK: - Key Handlers

    private func handleCommit(commandKey: Bool, optionKey: Bool) {
        if manager.hasCategorySelection {
            manager.commitExpandedModeSelection()
        } else if commandKey, manager.isAIIntent {
            manager.sendAIQuery()
        } else if commandKey, manager.isAIMode {
            manager.transferToReferencePane()
        } else {
            manager.commitSelection(commandKeyHeld: commandKey, optionKeyHeld: optionKey)
        }
    }

    private func handleEscape() {
        // Tier 1: Clear text if any
        if !manager.inputText.isEmpty {
            manager.inputText = ""
            manager.onInputChanged("")
            return
        }
        // Tier 2: Exit category search mode if active
        if manager.categorySearchMode != nil {
            manager.exitCategorySearchMode()
            return
        }
        // Tier 3: Exit expanded mode or close lens
        if manager.showCategoryButtons {
            manager.exitExpandedMode()
        } else {
            manager.reset()
            windowState.closeCommandLens()
            windowState.closeAddressLens()
            windowState.closeReferencePaneLens()
        }
    }

    private func handleTabKey() {
        // Search engine switching takes priority — Tab's primary purpose is
        // engine activation. Inline completion is available via Right Arrow.
        if let providerSuggestion = manager.suggestions.first(where: {
            if case .searchProvider = $0.type { return true }
            return false
        }), case let .searchProvider(engine) = providerSuggestion.type {
            manager.selectSearchProvider(engine)
            triggerProviderSwitchFeedback()
            return
        }

        if manager.inlineCompletion != nil {
            manager.acceptInlineCompletion()
        }
    }

    private func handleLeftArrow() -> Bool {
        guard manager.inputText.isEmpty, !isSmallMode else { return false }
        Task { _ = await manager.handleEmptyStateAction(direction: .left) }
        return true
    }

    private func handleRightArrow() -> Bool {
        guard manager.inputText.isEmpty, !isSmallMode else { return false }
        Task { _ = await manager.handleEmptyStateAction(direction: .right) }
        return true
    }

    private func handleDelete() -> Bool {
        if manager.showSearchEngineBadge, manager.inputText.isEmpty {
            manager.clearSearchProvider()
            triggerProviderClearFeedback()
            return true
        }
        return false
    }

    // MARK: - Feedback

    private func triggerProviderSwitchFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        providerSwitchScale = 1.03
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { providerSwitchScale = 1.0 }
    }

    private func triggerProviderClearFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        providerSwitchScale = 0.98
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { providerSwitchScale = 1.0 }
    }

    // MARK: - Auto-Show Timer

    private func startAutoShowButtonsTimer() {
        cancelAutoShowButtonsTimer()
        autoShowButtonsTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, manager.inputText.isEmpty, !manager.showCategoryButtons else { return }
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                manager.showCategoryButtonsForDiscoverability()
            }
        }
    }

    private func cancelAutoShowButtonsTimer() {
        autoShowButtonsTask?.cancel()
        autoShowButtonsTask = nil
    }

    // MARK: - Small Style Modifier

    func smallStyle() -> some View {
        environment(\.commandLensIsSmall, true)
    }
}

// MARK: - Category Button

/// Individual category button with glass effect and morph support.
private struct CategoryButton: View {
    let button: ExpandedModeButton
    let isSelected: Bool
    let index: Int
    let height: CGFloat
    let namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let iconSize: CGFloat = 18
    }

    var body: some View {
        buttonContent
            .frame(width: height, height: height)
            .glassEffect(.regular.interactive().tint(isSelected ? .appAccentColor : nil), in: Circle())
            .glassEffectID("category-\(button.id)", in: namespace)
            .glassEffectTransition(.materialize)
            .overlay {
                Circle()
                    .stroke(.secondary.opacity(0.7), lineWidth: 1)
                    .shadow(color: .secondary.opacity(0.25), radius: 3, x: 0, y: 1)
                    .shadow(color: .secondary.opacity(0.15), radius: 2, x: 0, y: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(button.label), Command \(index + 1)")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var buttonContent: some View {
        Image(systemName: button.icon)
            .font(.system(size: Layout.iconSize, weight: .medium))
            .foregroundStyle(isSelected ? .white : .secondary)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if isSelected {
            Circle().fill(Color.appAccentColor)
        }
    }
}
