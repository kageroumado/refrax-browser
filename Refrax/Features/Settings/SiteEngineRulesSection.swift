import SwiftUI

// MARK: - Site Engine Rules

/// Settings → Engines → Sites: the sites opened in a particular engine, editable in place.
struct SiteEngineRulesSection: View {
    @Environment(EngineRegistry.self) private var registry
    @Environment(BrowserSettings.self) private var settings

    @State private var isAdding = false
    @State private var newHost = ""

    var body: some View {
        let rules = settings.siteEngineRules
        Section {
            if rules.rules.isEmpty {
                Text("Every site opens in the default engine.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rules.rules, id: \.host) { rule in
                SiteEngineRuleRow(
                    rule: rule,
                    engines: registry.descriptors,
                    isUsable: registry.usableEngines.contains(rule.engine),
                    engineName: registry.displayName(for: rule.engine),
                    onRename: { rename(rule.host, to: $0) },
                    onEngineChange: { setEngine($0, for: rule.host) },
                    onRemove: { remove(rule.host) },
                )
            }
            HStack {
                Spacer()
                Button("Add Site…") {
                    newHost = ""
                    isAdding = true
                }
            }
        } header: {
            Text("Sites")
        } footer: {
            Text("""
            A site's rule covers its subdomains, and the most specific rule wins. A page moved with \
            Reload in… keeps its engine. Rules for engines that aren't installed have no effect.
            """)
        }
        .alert("Add Site", isPresented: $isAdding) {
            TextField("youtube.com", text: $newHost)
            Button("Add") { add(newHost) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pages on this site and its subdomains open in \(registry.displayName(for: engineForNewRule)).")
        }
    }

    /// The engine a new rule starts with: the first installed engine other than the default.
    private var engineForNewRule: EngineID {
        registry.descriptors.first { $0.id != settings.defaultEngineID }?.id ?? .chromium
    }

    private func add(_ host: String) {
        var rules = settings.siteEngineRules
        guard rules.rule(forHost: host) == nil, rules.set(engineForNewRule, for: host) != nil else { return }
        settings.siteEngineRules = rules
    }

    private func rename(_ host: String, to newHost: String) -> Bool {
        var rules = settings.siteEngineRules
        guard rules.rename(host, to: newHost) else { return false }
        settings.siteEngineRules = rules
        return true
    }

    private func setEngine(_ engine: EngineID, for host: String) {
        var rules = settings.siteEngineRules
        rules.set(engine, for: host)
        settings.siteEngineRules = rules
    }

    private func remove(_ host: String) {
        var rules = settings.siteEngineRules
        rules.remove(host: host)
        settings.siteEngineRules = rules
    }
}

// MARK: - Rule Row

/// One site rule: its host, edited in place, its engine, and removal.
private struct SiteEngineRuleRow: View {
    let rule: SiteEngineRule
    let engines: [EngineDescriptor]
    let isUsable: Bool
    let engineName: String
    /// Returns whether the new host was accepted.
    let onRename: (String) -> Bool
    let onEngineChange: @MainActor (EngineID) -> Void
    let onRemove: () -> Void

    @State private var draft: String?
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Host", text: Binding(get: { draft ?? rule.host }, set: { draft = $0 }))
                .textFieldStyle(.plain)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($isEditing)
                .onSubmit(commit)
                .onChange(of: isEditing) { _, editing in
                    if !editing {
                        commit()
                    }
                }

            if !isUsable {
                Text("Not installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Engine", selection: Binding(get: { rule.engine }, set: onEngineChange)) {
                ForEach(engines, id: \.id) { descriptor in
                    Text(descriptor.displayName).tag(descriptor.id)
                }
                if !engines.contains(where: { $0.id == rule.engine }) {
                    Text(engineName).tag(rule.engine)
                }
            }
            .labelsHidden()
            .fixedSize()

            Button("Remove \(rule.host)", systemImage: "minus.circle", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    /// Applies the edited host, or restores the rule's when it isn't a usable, unique host.
    private func commit() {
        guard let draft else { return }
        if !onRename(draft) {
            Logger.debug("Kept site rule \(rule.host): '\(draft)' isn't a new host name", category: Logger.engines)
        }
        self.draft = nil
    }
}
