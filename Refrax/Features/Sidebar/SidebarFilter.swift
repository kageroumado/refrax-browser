import SwiftData
import SwiftUI

// MARK: - Sidebar Control Button

/// A reusable button style for sidebar bottom controls.
///
/// Used for filter button, new space button, and potentially collapsed space picker.
/// Maintains consistent sizing and material styling across all control buttons.
struct SidebarControlButton: View {
    let icon: String
    let isActive: Bool
    let accessibilityID: String?
    let action: () -> Void

    init(
        icon: String,
        isActive: Bool = false,
        accessibilityID: String? = nil,
        action: @escaping () -> Void,
    ) {
        self.icon = icon
        self.isActive = isActive
        self.accessibilityID = accessibilityID
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.appAccentColor : .primary)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Layout.buttonCornerRadius))
        .if(accessibilityID != nil) { view in
            view.accessibilityIdentifier(accessibilityID!)
        }
    }
}

// MARK: - Sidebar Filter

/// Filter bar for the sidebar with collapsible behavior.
///
/// ## Layout States
///
/// **Collapsed (single row with space picker):**
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ [≡]  [Space Picker ...]             [+]     │
/// └─────────────────────────────────────────────┘
/// ```
///
/// **Expanded (full filter bar + space picker row):**
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ [≡]  Filter                        [⋯]      │
/// ├─────────────────────────────────────────────┤
/// │ [Space Picker fills width]          [+]     │
/// └─────────────────────────────────────────────┘
/// ```
///
/// The filter button morphs into the full filter bar using matchedGeometryEffect.
/// After 15 seconds of inactivity (no focus, no sheets, no active filters),
/// the layout collapses back to the single-row state.
struct SidebarFilter: View {
    @Environment(Sidebar.FilterManager.self) private var filterManager
    @Environment(\.modelContext) private var modelContext

    /// Whether the filter bar is expanded (showing full text field)
    @Binding var isExpanded: Bool
    
    /// Namespace for matched geometry morphing animation
    var morphNamespace: Namespace.ID
    
    @State private var showFilterManagementSheet = false
    @State private var showNewFilterSheet = false
    @State private var showFilterScopePopover = false
    @FocusState private var isTextFieldFocused: Bool

    /// Auto-collapse timer task
    @State private var collapseTask: Task<Void, any Error>?

    /// Current autocomplete suggestion based on typed text
    @State private var autocompleteSuggestion: FilterSuggestion?

    /// Observer for delete key presses to clear active filter when text is empty.
    /// Created lazily only when the expanded filter bar is visible.
    @State private var deleteKeyObserver: DeleteKeyObserver?
    
    // MARK: - Computed Properties
    
    /// Whether auto-collapse should be prevented
    private var shouldPreventCollapse: Bool {
        isTextFieldFocused ||
            showFilterManagementSheet ||
            showNewFilterSheet ||
            filterManager.hasActiveFilter
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if isExpanded {
                expandedFilterBar
            } else {
                collapsedFilterButton
            }
        }
        .onChange(of: shouldPreventCollapse) { _, shouldPrevent in
            if shouldPrevent {
                cancelCollapseTimer()
            } else if isExpanded {
                startCollapseTimer()
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                if !shouldPreventCollapse {
                    startCollapseTimer()
                }
            } else {
                cancelCollapseTimer()
                autocompleteSuggestion = nil
            }
        }
        .sheet(isPresented: $showFilterManagementSheet) {
            FilterManagementSheet(showNewFilterSheet: $showNewFilterSheet)
        }
        .sheet(isPresented: $showNewFilterSheet) {
            NewFilterSheet()
        }
    }
    
    // MARK: - Collapsed State (Button Only)
    
    private var collapsedFilterButton: some View {
        Button {
            withAnimation(Layout.morphAnimation) {
                isExpanded = true
            }
            // Start collapse timer immediately
            startCollapseTimer()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(filterManager.hasActiveFilter ? Color.appAccentColor : .primary)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Layout.buttonCornerRadius))
        .matchedGeometryEffect(id: "filterContainer", in: morphNamespace)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.8)
                    .combined(with: .opacity),
                removal: .scale(scale: 0.9)
                    .combined(with: .opacity),
            ),
        )
        .accessibilityIdentifier("sidebar-filter")
        .accessibilityLabel("Filter Tabs")
    }
    
    // MARK: - Expanded State (Full Filter Bar)

    private var expandedFilterBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let suggestion = autocompleteSuggestion {
                suggestionCapsule(suggestion)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: autocompleteSuggestion)
            }

            HStack(spacing: 0) {
                filterScopeButton

                searchTextField

                if filterManager.hasActiveFilter {
                    clearButton
                }

                manageFiltersButton
            }
            .frame(height: Layout.fieldHeight)
            .adaptiveBackground(.subtle, in: Capsule())
        }
        .matchedGeometryEffect(id: "filterContainer", in: morphNamespace)
        .transition(.opacity)
        .onAppear {
            startDeleteKeyObserver()
        }
        .task {
            // Defer focus by a short delay due to matchedGeometryEffect animation.
            // SwiftUI's focus system can fail when the TextField's geometry is still
            // being interpolated. Unlike simple conditional views (where a single
            // DispatchQueue.main.async suffices - see TabGroupHeaderView), the morph
            // animation requires the field to be properly positioned first.
            // 50ms is sufficient: focus just needs layout to stabilize, not the full
            // 350ms animation to complete. Tested with shorter delays (20ms) which
            // occasionally failed; 50ms is reliable while minimizing unfocused window.
            try? await Task.sleep(for: .milliseconds(50))
            isTextFieldFocused = true
        }
        .onDisappear {
            stopDeleteKeyObserver()
        }
    }

    /// Starts the delete key observer for clearing active filters.
    private func startDeleteKeyObserver() {
        let observer = DeleteKeyObserver()
        observer.onDeletePressed = { [filterManager] in
            // Only handle if text field is focused, text is empty, and a filter is active
            guard isTextFieldFocused,
                  filterManager.searchText.isEmpty,
                  filterManager.quickFilter != nil || filterManager.appliedSavedFilter != nil
            else {
                return false // Let the event through
            }

            clearActiveFilter()
            return true // Consume the event
        }
        deleteKeyObserver = observer
    }

    /// Stops and removes the delete key observer.
    private func stopDeleteKeyObserver() {
        deleteKeyObserver?.stopMonitoring()
        deleteKeyObserver = nil
    }

    // MARK: - Suggestion Capsule

    private func suggestionCapsule(_ suggestion: FilterSuggestion) -> some View {
        HStack(spacing: 6) {
            Image(systemName: suggestion.iconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(suggestion.displayName)
                .font(.system(size: 12, weight: .medium))

            Text("⇥")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.06), in: Capsule())
        .onTapGesture {
            applySuggestion(suggestion)
        }
    }
    
    // MARK: - Filter Scope Button (Left)
    
    private var filterScopeButton: some View {
        Button {
            showFilterScopePopover.toggle()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(filterManager.hasActiveFilter ? Color.appAccentColor : .secondary)
                .frame(width: Layout.iconButtonWidth, height: Layout.fieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .if(showFilterScopePopover) { view in
            view.popover(isPresented: $showFilterScopePopover, arrowEdge: .bottom) {
                filterScopePopoverContent
            }
        }
        .help("Filter Scope")
    }
    
    private var filterScopePopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // All Tabs option
            PageMenuItem(
                title: "All Tabs",
                icon: "tray.full",
                action: {
                    setQuickFilter(nil)
                    showFilterScopePopover = false
                },
            )

            // Quick filters
            ForEach(QuickFilter.allCases) { filter in
                PageMenuItem(
                    title: filter.displayName,
                    icon: filter.iconName,
                    action: {
                        setQuickFilter(filter)
                        showFilterScopePopover = false
                    },
                )
            }

            SavedFiltersPopoverSection { filter in
                applySavedFilter(filter)
                showFilterScopePopover = false
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 180)
    }
    
    // MARK: - Search Text Field (Center)

    /// Display name for the currently active filter (if any).
    private var activeFilterName: String? {
        if let savedFilter = filterManager.appliedSavedFilter {
            return savedFilter.displayName
        } else if let quickFilter = filterManager.quickFilter {
            return quickFilter.displayName
        }
        return nil
    }
    
    private var searchTextField: some View {
        @Bindable var filterManager = filterManager

        return HStack(spacing: 6) {
            // Active filter chip - shown whenever a filter is active
            if let filterName = activeFilterName {
                activeFilterChip(name: filterName)
            }

            TextField(
                activeFilterName != nil ? "" : "Filter",
                text: $filterManager.searchText,
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($isTextFieldFocused)
            .onChange(of: filterManager.searchText) { _, newValue in
                // Note: Actual filtering is debounced in FilterManager. Here we only
                // handle immediate feedback (autocomplete) and edge case (clearing).
                if newValue.isEmpty, filterManager.quickFilter == nil, filterManager.appliedSavedFilter == nil {
                    filterManager.clearFilters()
                }
                updateAutocompleteSuggestion(for: newValue)
            }
            .onSubmit {
                isTextFieldFocused = false
            }
            .onKeyPress(.tab) {
                if let suggestion = autocompleteSuggestion {
                    applySuggestion(suggestion)
                    return .handled
                }
                return .ignored
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: activeFilterName)
    }
    
    /// Chip displaying the active filter name. Tap to remove the filter.
    private func activeFilterChip(name: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .background(.primary.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            clearActiveFilter()
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    /// Clears the currently active quick filter or saved filter.
    private func clearActiveFilter() {
        filterManager.setQuickFilter(nil)
        filterManager.appliedSavedFilter = nil
    }
    
    // MARK: - Clear Button
    
    private var clearButton: some View {
        Button {
            isTextFieldFocused = false
            clearAllFilters()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Clear Filters")
    }
    
    // MARK: - Manage Filters Button (Right)

    private var manageFiltersButton: some View {
        Button {
            showFilterManagementSheet = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Layout.iconButtonWidth, height: Layout.fieldHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Manage Filters")
    }
    
    // MARK: - Timer Management
    
    private func startCollapseTimer() {
        cancelCollapseTimer()

        collapseTask = Task {
            try await Task.sleep(for: .seconds(15))

            // Re-check conditions before collapsing
            await MainActor.run {
                if !shouldPreventCollapse, isExpanded {
                    withAnimation(Layout.morphAnimation) {
                        isExpanded = false
                    }
                }
            }
        }
    }
    
    private func cancelCollapseTimer() {
        collapseTask?.cancel()
        collapseTask = nil
    }
    
    // MARK: - Actions

    private func setQuickFilter(_ filter: QuickFilter?) {
        filterManager.setQuickFilter(filter)
    }

    private func applySavedFilter(_ filter: SavedFilter) {
        filterManager.applySavedFilter(filter)
    }

    private func clearAllFilters() {
        withAnimation(Layout.standardAnimation) {
            filterManager.clearFilters()
        }
    }

    // MARK: - Autocomplete

    /// Updates the autocomplete suggestion based on typed text.
    private func updateAutocompleteSuggestion(for text: String) {
        guard !text.isEmpty, filterManager.quickFilter == nil, filterManager.appliedSavedFilter == nil else {
            autocompleteSuggestion = nil
            return
        }

        // Check quick filters using keyword matching
        if let matchingFilter = QuickFilter.matching(searchText: text) {
            autocompleteSuggestion = .quickFilter(matchingFilter)
            return
        }

        // Check saved filters by display name prefix (on-demand fetch)
        let lowercased = text.lowercased()
        let descriptor = FetchDescriptor<SavedFilter>(sortBy: [SortDescriptor(\.name)])
        if let filters = try? modelContext.fetch(descriptor) {
            for filter in filters {
                if filter.displayName.lowercased().hasPrefix(lowercased) {
                    autocompleteSuggestion = .savedFilter(filter)
                    return
                }
            }
        }

        autocompleteSuggestion = nil
    }

    /// Applies the given suggestion and clears the search text.
    private func applySuggestion(_ suggestion: FilterSuggestion) {
        filterManager.searchText = ""
        autocompleteSuggestion = nil

        switch suggestion {
        case let .quickFilter(filter):
            setQuickFilter(filter)
        case let .savedFilter(filter):
            applySavedFilter(filter)
        }
    }
}

// MARK: - Saved Filters Popover Section

/// Child view that owns its own `@Query` for saved filters.
///
/// Isolated here so the query only activates when the popover is open,
/// preventing coarse-grained SwiftData invalidation from cascading
/// through the always-present `SidebarFilter` view.
private struct SavedFiltersPopoverSection: View {
    @Query(sort: \SavedFilter.name) private var savedFilters: [SavedFilter]
    let onSelect: (SavedFilter) -> Void

    var body: some View {
        if !savedFilters.isEmpty {
            Divider()
                .padding(.vertical, 4)

            ForEach(savedFilters) { filter in
                PageMenuItem(
                    title: filter.displayName,
                    icon: "line.3.horizontal.decrease.circle",
                    action: { onSelect(filter) },
                )
            }
        }
    }
}

// MARK: - Filter Suggestion

/// Represents an autocomplete suggestion for the filter field.
enum FilterSuggestion: Equatable {
    case quickFilter(QuickFilter)
    case savedFilter(SavedFilter)

    var displayName: String {
        switch self {
        case let .quickFilter(filter): filter.displayName
        case let .savedFilter(filter): filter.displayName
        }
    }

    var iconName: String {
        switch self {
        case let .quickFilter(filter): filter.iconName
        case .savedFilter: "line.3.horizontal.decrease.circle"
        }
    }
}

// MARK: - Layout Constants

private enum Layout {
    static let fieldHeight: CGFloat = 28
    static let buttonSize: CGFloat = 32
    static let buttonCornerRadius: CGFloat = 16
    static let iconButtonWidth: CGFloat = 32
    static let buttonHorizontalPadding: CGFloat = 6
    static let standardAnimation = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let morphAnimation = Animation.spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0.1)
}

// MARK: - Filter Management Sheet

/// Sheet for managing saved filters
struct FilterManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Sidebar.FilterManager.self) private var filterManager
    @Query(sort: \SavedFilter.name) private var savedFilters: [SavedFilter]
    
    /// Binding to parent's sheet state for proper collapse timer management
    @Binding var showNewFilterSheet: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Filters")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            Divider()
            
            // Filter list
            if savedFilters.isEmpty {
                emptyStateView
            } else {
                filterListView
            }
            
            Divider()
            
            // Add button
            HStack {
                Spacer()
                Button {
                    dismiss()
                    // Small delay to allow dismiss animation before showing new sheet
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        showNewFilterSheet = true
                    }
                } label: {
                    Label("New Filter", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Saved Filters")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Create custom filters to quickly find specific tabs")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var filterListView: some View {
        List {
            ForEach(savedFilters) { filter in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(filter.displayName)
                            .font(.headline)
                        
                        HStack(spacing: 8) {
                            if !filter.searchText.isEmpty {
                                Text(filter.searchText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let unreadFilter = filter.searchUnread {
                                Text(unreadFilter ? "Unread Only" : "Read Only")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Material.thin)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    Spacer()
                    Button {
                        deleteFilter(filter)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func deleteFilter(_ filter: SavedFilter) {
        if filterManager.appliedSavedFilter?.id == filter.id {
            filterManager.clearFilters()
        }
        modelContext.delete(filter)
        try? modelContext.save()
    }
}

// MARK: - New Filter Sheet

/// Sheet for creating a new saved filter
struct NewFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Sidebar.FilterManager.self) private var filterManager
    
    @State private var filterName = ""
    @State private var searchText = ""
    @State private var searchInTitle = true
    @State private var searchInURL = true
    @State private var searchUnread: Bool? = nil
    
    private var isFilterInvalid: Bool {
        guard !filterName.isEmpty else { return true }
        
        let hasTextFilter = !searchText.isEmpty && (searchInTitle || searchInURL)
        let hasUnreadFilter = searchUnread != nil
        
        return !hasTextFilter && !hasUnreadFilter
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("New Filter")
                .font(.headline)
            
            Form {
                TextField("Filter Name", text: $filterName)
                TextField("Search Text", text: $searchText)
                
                Toggle("Search in Title", isOn: $searchInTitle)
                Toggle("Search in URL", isOn: $searchInURL)
                
                Divider()
                
                Picker("Show Tabs", selection: $searchUnread) {
                    Text("All Tabs").tag(nil as Bool?)
                    Text("Unread Only").tag(true as Bool?)
                    Text("Read Only").tag(false as Bool?)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save") {
                    saveFilter()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isFilterInvalid)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 400)
    }
    
    private func saveFilter() {
        let filter = SavedFilter(
            name: filterName,
            searchText: searchText,
            searchInTitle: searchInTitle,
            searchInURL: searchInURL,
            searchUnread: searchUnread,
        )
        
        modelContext.insert(filter)
        try? modelContext.save()
        
        dismiss()
    }
}
