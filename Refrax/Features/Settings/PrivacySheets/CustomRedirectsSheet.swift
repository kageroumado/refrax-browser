import SwiftUI

// MARK: - Custom Redirects Sheet

struct CustomRedirectsSheet: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRedirect: CustomRedirect?
    @State private var showAddSheet = false

    private var privacySettings: PrivacyProtectionSettings {
        settings.privacyProtection
    }

    var body: some View {
        NavigationStack {
            List(selection: $selectedRedirect) {
                ForEach(privacySettings.customRedirects.sorted(by: { $0.order < $1.order })) { redirect in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(redirect.name)
                                .font(.headline)
                            Text("\(redirect.sourcePattern) → \(redirect.destinationTemplate)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { redirect.isEnabled },
                            set: { redirect.isEnabled = $0 },
                        ))
                        .labelsHidden()
                    }
                    .tag(redirect)
                }
                .onDelete { indexSet in
                    let sorted = privacySettings.customRedirects.sorted(by: { $0.order < $1.order })
                    for index in indexSet {
                        if let idx = privacySettings.customRedirects.firstIndex(where: { $0.id == sorted[index].id }) {
                            privacySettings.customRedirects.remove(at: idx)
                        }
                    }
                }
            }
            .overlay {
                if privacySettings.customRedirects.isEmpty {
                    ContentUnavailableView {
                        Label("No Custom Redirects", systemImage: "arrow.triangle.swap")
                    } description: {
                        Text("Add redirect rules to transform URLs during navigation.")
                    } actions: {
                        Button("Add Redirect") {
                            showAddSheet = true
                        }
                    }
                }
            }
            .navigationTitle("Custom Redirects")
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
            AddCustomRedirectSheet()
        }
    }
}

// MARK: - Add Custom Redirect Sheet

struct AddCustomRedirectSheet: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sourcePattern = ""
    @State private var destinationTemplate = ""

    private var privacySettings: PrivacyProtectionSettings {
        settings.privacyProtection
    }

    private var isValid: Bool {
        !name.isEmpty && !sourcePattern.isEmpty && !destinationTemplate.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    TextField("Source Pattern", text: $sourcePattern)
                        .textFieldStyle(.roundedBorder)
                    Text("Use * for wildcards. Example: twitter.com/*")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Destination Template", text: $destinationTemplate)
                        .textFieldStyle(.roundedBorder)
                    Text("Use $1, $2, etc. for captured wildcards. Example: nitter.net/$1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Redirect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let redirect = CustomRedirect(
                            name: name,
                            sourcePattern: sourcePattern,
                            destinationTemplate: destinationTemplate,
                            order: privacySettings.customRedirects.count,
                        )
                        privacySettings.customRedirects.append(redirect)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
