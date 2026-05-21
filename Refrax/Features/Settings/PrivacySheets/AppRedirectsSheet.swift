import SwiftUI

// MARK: - App Redirects Sheet

struct AppRedirectsSheet: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false

    private var privacySettings: PrivacyProtectionSettings {
        settings.privacyProtection
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(privacySettings.appRedirectRules.sorted(by: { $0.order < $1.order })) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.name)
                                .font(.headline)
                            Text(rule.domainPattern + (rule.pathPattern.map(\.self) ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { rule.isEnabled = $0 },
                        ))
                        .labelsHidden()
                    }
                }
                .onDelete { indexSet in
                    let sorted = privacySettings.appRedirectRules.sorted(by: { $0.order < $1.order })
                    for index in indexSet {
                        if let idx = privacySettings.appRedirectRules.firstIndex(where: { $0.id == sorted[index].id }) {
                            privacySettings.appRedirectRules.remove(at: idx)
                        }
                    }
                }
            }
            .overlay {
                if privacySettings.appRedirectRules.isEmpty {
                    ContentUnavailableView {
                        Label("No App Redirects", systemImage: "app.badge.checkmark")
                    } description: {
                        Text("Add rules to open specific URLs in external applications.")
                    } actions: {
                        Button("Add Rule") {
                            showAddSheet = true
                        }
                    }
                }
            }
            .navigationTitle("App Redirects")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .sheet(isPresented: $showAddSheet) {
            AddAppRedirectSheet()
        }
    }
}

// MARK: - Add App Redirect Sheet

struct AddAppRedirectSheet: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var domainPattern = ""
    @State private var pathPattern = ""
    @State private var bundleID = ""

    private var privacySettings: PrivacyProtectionSettings {
        settings.privacyProtection
    }

    private var isValid: Bool {
        !name.isEmpty && !domainPattern.isEmpty && !bundleID.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    TextField("Domain Pattern", text: $domainPattern)
                        .textFieldStyle(.roundedBorder)
                    Text("Use * for wildcards. Example: *.youtube.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Path Pattern (optional)", text: $pathPattern)
                        .textFieldStyle(.roundedBorder)
                    Text("Example: /watch*")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("App Bundle ID", text: $bundleID)
                        .textFieldStyle(.roundedBorder)
                    Text("Example: com.colliderli.iina")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Common apps picker
                    HStack {
                        Text("Common apps:")
                            .foregroundStyle(.secondary)
                        Picker("", selection: $bundleID) {
                            Text("Select…").tag("")
                            Text("IINA").tag(AppRedirectRule.CommonApps.iina)
                            Text("Spotify").tag(AppRedirectRule.CommonApps.spotify)
                            Text("Zoom").tag(AppRedirectRule.CommonApps.zoom)
                            Text("Slack").tag(AppRedirectRule.CommonApps.slack)
                            Text("Discord").tag(AppRedirectRule.CommonApps.discord)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add App Redirect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let rule = AppRedirectRule(
                            name: name,
                            domainPattern: domainPattern,
                            pathPattern: pathPattern.isEmpty ? nil : pathPattern,
                            targetAppBundleID: bundleID,
                            order: privacySettings.appRedirectRules.count,
                        )
                        privacySettings.appRedirectRules.append(rule)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}
