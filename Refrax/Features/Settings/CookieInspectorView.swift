import SwiftUI
import WebKit

/// Cookie inspector view for viewing, editing, and managing all site cookies.
///
/// Displays a searchable, filterable list of all cookies across all data stores
/// with inline editing capabilities and bulk operations.
struct CookieInspectorView: View {
    @Environment(CookieInspectorManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false
    @State private var showDeleteAllConfirmation = false
    @State private var editingCookie: CookieEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await manager.loadAllCookies() }
        .sheet(isPresented: $showAddSheet) {
            CookieFormSheet(availableStores: [.default] + manager.allStores.filter { $0 != .default }) { model, storeInfo in
                Task { await manager.addCookie(model, to: storeInfo) }
            }
        }
        .sheet(item: $editingCookie) { entry in
            CookieFormSheet(entry: entry) { model, _ in
                Task { await manager.updateCookie(entry, with: model) }
            }
        }
        .alert("Delete Cookies", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await manager.deleteFilteredCookies() }
            }
        } message: {
            Text("Delete \(manager.filteredCookies.count) cookies? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Cookie Inspector")
                .font(.headline)

            Spacer()

            Text("\(manager.totalCookieCount) cookies")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        @Bindable var manager = manager

        return HStack(spacing: 12) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search cookies...", text: $manager.searchText)
                    .textFieldStyle(.plain)

                if !manager.searchText.isEmpty {
                    Button {
                        manager.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 250)

            // Store filter
            Picker("Store", selection: $manager.selectedStoreFilter) {
                Text("All Stores").tag(DataStoreInfo?.none)
                ForEach(manager.allStores) { store in
                    Text(store.displayName).tag(DataStoreInfo?.some(store))
                }
            }
            .labelsHidden()
            .fixedSize()

            // Domain filter
            Picker("Domain", selection: $manager.selectedDomainFilter) {
                Text("All Domains").tag(String?.none)
                ForEach(manager.allDomains, id: \.self) { domain in
                    Text(domain).tag(String?.some(domain))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)

            Spacer()

            // Actions
            Button {
                showAddSheet = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                Task { await manager.loadAllCookies() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(manager.filteredCookies.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if manager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if manager.filteredCookies.isEmpty {
            emptyState
        } else {
            cookieTable
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                manager.searchText.isEmpty ? "No Cookies" : "No Results",
                systemImage: manager.searchText.isEmpty ? "archivebox" : "magnifyingglass",
            )
        } description: {
            if manager.searchText.isEmpty {
                Text("No cookies stored across any data stores.")
            } else {
                Text("No cookies match \"\(manager.searchText)\"")
            }
        }
    }

    private var cookieTable: some View {
        Table(manager.filteredCookies, selection: Binding(
            get: { manager.selectedCookie?.id },
            set: { id in manager.selectedCookie = manager.filteredCookies.first { $0.id == id } },
        )) {
            TableColumn("Domain") { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.cookie.domain)
                        .lineLimit(1)
                    Text(entry.storeInfo.displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn("Name") { entry in
                HStack(spacing: 6) {
                    Text(entry.cookie.name)
                        .lineLimit(1)
                    flagBadges(for: entry.cookie)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("Value") { entry in
                Text(entry.cookie.truncatedValue)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 150, ideal: 200)

            TableColumn("Expires") { entry in
                Text(entry.cookie.expirationDescription)
                    .foregroundStyle(.tertiary)
            }
            .width(70)

            TableColumn("") { entry in
                HStack(spacing: 4) {
                    Button {
                        editingCookie = entry
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        Task { await manager.deleteCookie(entry) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .width(50)
        }
        .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in
            if let id = ids.first,
               let entry = manager.filteredCookies.first(where: { $0.id == id }) {
                editingCookie = entry
            }
        }
    }

    @ViewBuilder
    private func flagBadges(for cookie: HTTPCookie) -> some View {
        HStack(spacing: 4) {
            if cookie.isSecure {
                CookieFlagBadge(text: "S", color: .green, help: "Secure")
            }
            if cookie.isHTTPOnly {
                CookieFlagBadge(text: "H", color: .blue, help: "HttpOnly")
            }
            if cookie.sameSitePolicy?.rawValue.lowercased() == "strict" {
                CookieFlagBadge(text: "X", color: .orange, help: "SameSite=Strict")
            }
        }
    }
}

// MARK: - Cookie Flag Badge

/// Compact badge showing cookie flags (Secure, HttpOnly, SameSite).
struct CookieFlagBadge: View {
    let text: String
    let color: Color
    var help: String?

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            .help(help ?? "")
    }
}

// MARK: - Cookie Form Sheet

/// Unified sheet for adding or editing cookies.
///
/// Supports two modes:
/// - **Add mode**: When `entry` is nil, allows selecting a data store and entering a new domain.
/// - **Edit mode**: When `entry` is provided, domain and store are read-only.
struct CookieFormSheet: View {
    /// The cookie being edited, or nil for add mode.
    let entry: CookieEntry?

    /// Available stores for the picker (add mode only).
    let availableStores: [DataStoreInfo]

    /// Called with the edited model and target store when saved.
    let onSave: (CookieEditModel, DataStoreInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var model: CookieEditModel
    @State private var selectedStore: DataStoreInfo
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, value, domain }

    private var isAddMode: Bool { entry == nil }

    init(
        entry: CookieEntry? = nil,
        availableStores: [DataStoreInfo] = [.default],
        onSave: @escaping (CookieEditModel, DataStoreInfo) -> Void,
    ) {
        self.entry = entry
        self.availableStores = availableStores
        self.onSave = onSave

        if let entry {
            _model = State(initialValue: CookieEditModel(from: entry.cookie))
            _selectedStore = State(initialValue: entry.storeInfo)
        } else {
            _model = State(initialValue: CookieEditModel())
            _selectedStore = State(initialValue: .default)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            formContent
        }
        .frame(width: 420, height: isAddMode ? 500 : 460)
        .onAppear { focusedField = .name }
    }

    private var sheetHeader: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            Text(isAddMode ? "Add Cookie" : "Edit Cookie")
                .font(.headline)

            Spacer()

            Button(isAddMode ? "Add" : "Save") {
                onSave(model, selectedStore)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!model.isValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var formContent: some View {
        Form {
            if isAddMode {
                Section {
                    Picker("Data Store", selection: $selectedStore) {
                        ForEach(availableStores) { store in
                            Text(store.displayName).tag(store)
                        }
                    }
                }
            } else if let entry {
                Section {
                    LabeledContent("Data Store") {
                        Text(entry.storeInfo.displayName)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Domain") {
                        Text(model.domain)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                TextField("Name", text: $model.name)
                    .focused($focusedField, equals: .name)

                TextField("Value", text: $model.value, axis: .vertical)
                    .focused($focusedField, equals: .value)
                    .lineLimit(3 ... 6)

                if isAddMode {
                    TextField("Domain", text: $model.domain)
                        .focused($focusedField, equals: .domain)
                }

                TextField("Path", text: $model.path)
            }

            Section {
                DatePicker("Expires", selection: expiresBinding, displayedComponents: [.date, .hourAndMinute])
                Toggle("Session Cookie", isOn: isSessionBinding)
            }

            Section("Flags") {
                Toggle("Secure", isOn: $model.isSecure)
                Toggle("HttpOnly", isOn: $model.isHttpOnly)
                Picker("SameSite", selection: $model.sameSite) {
                    ForEach(CookieEditModel.SameSitePolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var expiresBinding: Binding<Date> {
        Binding(
            get: { model.expiresDate ?? CookieEditModel.defaultExpirationDate },
            set: { model.expiresDate = $0 },
        )
    }

    private var isSessionBinding: Binding<Bool> {
        Binding(
            get: { model.expiresDate == nil },
            set: { model.expiresDate = $0 ? nil : CookieEditModel.defaultExpirationDate },
        )
    }
}
