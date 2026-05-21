import SwiftUI
import WebKit

/// Site-specific cookie view showing cookies for a single domain.
///
/// Uses the central `CookieInspectorManager` but filters to show only cookies
/// matching the specified domain. Accessible from the page menu.
struct SiteCookiesView: View {
    let domain: String
    let dataStore: WKWebsiteDataStore

    @Environment(CookieInspectorManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false
    @State private var showDeleteAllConfirmation = false
    @State private var editingCookie: CookieEntry?

    /// Cookies filtered to this domain.
    private var domainCookies: [CookieEntry] {
        manager.allCookies.filter { $0.matchesDomain(domain) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 450, height: 420)
        .task {
            await manager.loadAllCookies()
        }
        .sheet(isPresented: $showAddSheet) {
            SiteCookieAddSheet(domain: domain, dataStore: dataStore)
        }
        .sheet(item: $editingCookie) { entry in
            CookieFormSheet(entry: entry) { model, _ in
                Task { await manager.updateCookie(entry, with: model) }
            }
        }
        .alert("Delete All Cookies", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteDomainCookies() }
            }
        } message: {
            Text("Delete all \(domainCookies.count) cookies for \(domain)? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cookies")
                    .font(.headline)
                Text(domain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    showDeleteAllConfirmation = true
                } label: {
                    Label("Delete All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(domainCookies.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if manager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if domainCookies.isEmpty {
            ContentUnavailableView {
                Label("No Cookies", systemImage: "archivebox")
            } description: {
                Text("This site has no cookies stored.")
            }
        } else {
            cookieList
        }
    }

    private var cookieList: some View {
        VStack(spacing: 0) {
            List(domainCookies) { entry in
                CookieListRow(entry: entry) {
                    editingCookie = entry
                } onDelete: {
                    Task { await manager.deleteCookie(entry) }
                }
            }

            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                CookieFlagBadge(text: "S", color: .green)
                Text("Secure")
            }
            HStack(spacing: 4) {
                CookieFlagBadge(text: "H", color: .blue)
                Text("HttpOnly")
            }
            Spacer()
            Text("Expires")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.fill.quaternary)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func deleteDomainCookies() async {
        for entry in domainCookies {
            await manager.deleteCookie(entry)
        }
    }
}

// MARK: - Cookie List Row

private struct CookieListRow: View {
    let entry: CookieEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.cookie.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    flagBadges
                }

                Text(entry.cookie.truncatedValue)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(entry.cookie.expirationDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            if isHovered {
                HStack(spacing: 4) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)

                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Edit Cookie...") { onEdit() }
            Button("Copy Value") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.cookie.value, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder
    private var flagBadges: some View {
        HStack(spacing: 4) {
            if entry.cookie.isSecure {
                CookieFlagBadge(text: "S", color: .green)
            }
            if entry.cookie.isHTTPOnly {
                CookieFlagBadge(text: "H", color: .blue)
            }
        }
    }
}

// MARK: - Site Cookie Add Sheet

/// Site-specific add sheet that pre-fills the domain and uses the site's data store.
private struct SiteCookieAddSheet: View {
    let domain: String
    let dataStore: WKWebsiteDataStore

    @Environment(CookieInspectorManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var model: CookieEditModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, value }

    init(domain: String, dataStore: WKWebsiteDataStore) {
        self.domain = domain
        self.dataStore = dataStore
        _model = State(initialValue: CookieEditModel(domain: domain))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Add Cookie")
                    .font(.headline)

                Spacer()

                Button("Add") {
                    let storeInfo: DataStoreInfo = dataStore == .default() ? .default : manager.allStores.first ?? .default
                    Task { await manager.addCookie(model, to: storeInfo) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Form {
                Section {
                    LabeledContent("Domain") {
                        Text(domain)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Name", text: $model.name)
                        .focused($focusedField, equals: .name)
                    TextField("Value", text: $model.value, axis: .vertical)
                        .focused($focusedField, equals: .value)
                        .lineLimit(3 ... 6)
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
        .frame(width: 380, height: 420)
        .onAppear { focusedField = .name }
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
