import SwiftUI
import UniformTypeIdentifiers

// MARK: - Customization Type

/// The type of user customization being managed.
enum UserCustomizationType: String, CaseIterable, Identifiable {
    case styles
    case scripts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .styles: "User Styles"
        case .scripts: "User Scripts"
        }
    }

    var singularName: String {
        switch self {
        case .styles: "style"
        case .scripts: "script"
        }
    }

    var icon: String {
        switch self {
        case .styles: "paintbrush.pointed"
        case .scripts: "applescript"
        }
    }

    var emptyStateIcon: String {
        switch self {
        case .styles: "paintbrush.pointed"
        case .scripts: "applescript"
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .styles: "Create a new style or import one from a file."
        case .scripts: "Create a new script or import a .user.js file."
        }
    }

    var footerText: String {
        switch self {
        case .styles: "User styles apply custom CSS to matching websites. Styles are applied in order of installation."
        case .scripts: "User scripts run JavaScript on matching websites. Supports Greasemonkey/Tampermonkey metadata and GM_* APIs."
        }
    }
}

// MARK: - User Customization Settings View

/// Unified settings panel for managing user content (styles and scripts).
struct UserCustomizationSettingsView: View {
    let highlightedItemId: String?

    @State private var selectedType: UserCustomizationType = .styles

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("Content Type", selection: $selectedType) {
                ForEach(UserCustomizationType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Content based on selection
            switch selectedType {
            case .styles:
                UserStylesContentView(highlightedItemId: highlightedItemId)
            case .scripts:
                UserScriptsContentView(highlightedItemId: highlightedItemId)
            }
        }
    }
}

// MARK: - User Styles Content View

private struct UserStylesContentView: View {
    let highlightedItemId: String?

    @State private var showingEditor = false
    @State private var showingImportPicker = false
    @State private var editingStyle: UserStyle?

    private var userStyleManager: UserStyleManager {
        NSApplication.shared.typedDelegate.userStyleManager
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Create New Style", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingImportPicker = true
                } label: {
                    Label("Import Style…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Installed styles list
            if userStyleManager.styles.isEmpty {
                emptyState
            } else {
                stylesList
            }

            // Footer
            footerView
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.css, UTType(filenameExtension: "user.css") ?? .css],
            allowsMultipleSelection: false,
        ) { result in
            handleStyleImport(result)
        }
        .sheet(item: $editingStyle) { style in
            StyleEditorSheet(style: style, isNew: false) {
                editingStyle = nil
            }
        }
        .sheet(isPresented: $showingEditor) {
            StyleEditorSheet(style: nil, isNew: true) {
                showingEditor = false
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Styles", systemImage: "paintbrush.pointed")
        } description: {
            Text("Create a new style or import one from a file.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stylesList: some View {
        List {
            ForEach(userStyleManager.stylesGroupedByDomain(), id: \.domain) { group in
                DisclosureGroup {
                    ForEach(group.styles) { style in
                        CustomizationRowView(
                            displayName: style.displayName,
                            isEnabled: style.isEnabled,
                            version: style.version,
                            author: style.author,
                            isRemote: style.isRemote,
                            itemType: "style",
                            onToggle: { userStyleManager.toggleEnabled(style) },
                            onEdit: { editingStyle = style },
                            onDelete: { userStyleManager.delete(style) },
                        )
                    }
                } label: {
                    HStack {
                        Text(group.domain)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(group.styles.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footerView: some View {
        Text("User styles apply custom CSS to matching websites. Styles are applied in order of installation.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.fill.quaternary)
    }

    private func handleStyleImport(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result {
                Logger.error("Failed to import style: \(error)", category: Logger.tabs)
            }
            return
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        if let style = userStyleManager.importFromFile(url) {
            editingStyle = style
        }
    }
}

// MARK: - Customization Row View

private struct CustomizationRowView: View {
    let displayName: String
    let isEnabled: Bool
    let version: String?
    let author: String?
    let isRemote: Bool
    let itemType: String
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() },
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .fontWeight(.medium)
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                HStack(spacing: 8) {
                    if let version {
                        Text("v\(version)")
                    }
                    if let author {
                        Text("by \(author)")
                    }
                    if isRemote {
                        Image(systemName: "cloud")
                            .imageScale(.small)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit \(itemType)")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete \(itemType)")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - User Scripts Content View

private struct UserScriptsContentView: View {
    let highlightedItemId: String?

    @State private var showingEditor = false
    @State private var showingImportPicker = false
    @State private var editingScript: UserScript?

    private var userScriptManager: UserScriptManager? {
        NSApplication.shared.typedDelegate.userScriptManager
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Create New Script", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingImportPicker = true
                } label: {
                    Label("Import Script…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Installed scripts list
            if let manager = userScriptManager, !manager.scripts.isEmpty {
                scriptsList(manager: manager)
            } else {
                emptyState
            }

            // Footer
            footerView
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.javaScript, UTType(filenameExtension: "user.js") ?? .javaScript],
            allowsMultipleSelection: false,
        ) { result in
            handleScriptImport(result)
        }
        .sheet(item: $editingScript) { script in
            ScriptEditorSheet(script: script, isNew: false) {
                editingScript = nil
            }
        }
        .sheet(isPresented: $showingEditor) {
            ScriptEditorSheet(script: nil, isNew: true) {
                showingEditor = false
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Scripts", systemImage: "applescript")
        } description: {
            Text("Create a new script or import a .user.js file.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scriptsList(manager: UserScriptManager) -> some View {
        List {
            ForEach(manager.scriptsGroupedByDomain(), id: \.domain) { group in
                DisclosureGroup {
                    ForEach(group.scripts) { script in
                        CustomizationRowView(
                            displayName: script.displayName,
                            isEnabled: script.isEnabled,
                            version: script.version,
                            author: script.author,
                            isRemote: script.isRemote,
                            itemType: "script",
                            onToggle: { manager.toggleEnabled(script) },
                            onEdit: { editingScript = script },
                            onDelete: { manager.delete(script) },
                        )
                    }
                } label: {
                    HStack {
                        Text(group.domain)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(group.scripts.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footerView: some View {
        Text("User scripts run JavaScript on matching websites. Supports Greasemonkey/Tampermonkey metadata and GM_* APIs.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.fill.quaternary)
    }

    private func handleScriptImport(_ result: Result<[URL], any Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result {
                Logger.error("Failed to import script: \(error)", category: Logger.tabs)
            }
            return
        }

        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let source = try await Task.detached {
                    try String(contentsOf: url, encoding: .utf8)
                }.value

                if let manager = userScriptManager {
                    let script = try manager.install(from: source, sourceURL: url)
                    editingScript = script
                }
            } catch {
                Logger.error("Failed to import script: \(error)", category: Logger.tabs)
            }
        }
    }
}

// MARK: - Script Editor Sheet

private struct ScriptEditorSheet: View {
    let script: UserScript?
    let isNew: Bool
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var source: String = ""
    @State private var matchPatterns: String = ""
    @State private var showingDeleteConfirmation = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case patterns
        case source
    }

    private var userScriptManager: UserScriptManager? {
        NSApplication.shared.typedDelegate.userScriptManager
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Script" : "Edit Script")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isNew ? "Create" : "Save") {
                    saveScript()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || source.isEmpty)
            }
            .padding()

            Divider()

            // Form content
            Form {
                Section("Script Info") {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                }

                Section {
                    TextField("Match Patterns (one per line)", text: $matchPatterns, axis: .vertical)
                        .lineLimit(3 ... 5)
                        .focused($focusedField, equals: .patterns)
                } header: {
                    Text("URL Patterns")
                } footer: {
                    Text("Chrome-style patterns like \"*://*.github.com/*\" or Greasemonkey wildcards.")
                }

                Section {
                    TextEditor(text: $source)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 250)
                        .focused($focusedField, equals: .source)
                } header: {
                    Text("JavaScript")
                } footer: {
                    Text("Include a ==UserScript== metadata block for @grant, @run-at, and other options.")
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Script", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 700, height: 600)
        .onAppear {
            loadScript()
            focusedField = .name
        }
        .confirmationDialog(
            "Delete Script?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                if let script, let manager = userScriptManager {
                    manager.delete(script)
                }
                onDismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func loadScript() {
        guard let script else { return }

        name = script.name
        source = script.source
        matchPatterns = script.matchPatterns.joined(separator: "\n")
    }

    private func saveScript() {
        let patterns = matchPatterns
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let manager = userScriptManager else { return }

        if let existingScript = script {
            let newSource = buildSourceWithMetadata(patterns: patterns)
            do {
                try manager.update(existingScript, newSource: newSource)
            } catch {
                Logger.error("Failed to update script: \(error)", category: Logger.tabs)
            }
        } else {
            let newSource = buildSourceWithMetadata(patterns: patterns)
            do {
                _ = try manager.install(from: newSource, sourceURL: nil)
            } catch {
                Logger.error("Failed to create script: \(error)", category: Logger.tabs)
            }
        }

        onDismiss()
    }

    private func buildSourceWithMetadata(patterns: [String]) -> String {
        if source.contains("==UserScript==") {
            return source
        }

        let patternLines = patterns.map { "// @match        \($0)" }.joined(separator: "\n")
        return """
        // ==UserScript==
        // @name         \(name)
        // @namespace    local
        // @version      1.0
        \(patternLines)
        // @grant        none
        // ==/UserScript==
        
        \(source)
        """
    }
}

// MARK: - Style Editor Sheet

struct StyleEditorSheet: View {
    let style: UserStyle?
    let isNew: Bool
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var css: String = ""
    @State private var domainPatterns: String = ""
    @State private var isGlobal: Bool = false
    @State private var showingDeleteConfirmation = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case domains
        case css
    }

    private var userStyleManager: UserStyleManager {
        NSApplication.shared.typedDelegate.userStyleManager
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isNew ? "New Style" : "Edit Style")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isNew ? "Create" : "Save") {
                    saveStyle()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || (css.isEmpty && !isGlobal))
            }
            .padding()

            Divider()

            // Form content
            Form {
                Section("Style Info") {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)

                    Toggle("Apply to all websites", isOn: $isGlobal)
                }

                if !isGlobal {
                    Section {
                        TextField("Domains (one per line)", text: $domainPatterns, axis: .vertical)
                            .lineLimit(3 ... 5)
                            .focused($focusedField, equals: .domains)
                    } header: {
                        Text("Domain Patterns")
                    } footer: {
                        Text("Enter domains like \"github.com\" or \"*.gitlab.com\" for wildcards.")
                    }
                }

                Section {
                    TextEditor(text: $css)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .focused($focusedField, equals: .css)
                } header: {
                    Text("CSS")
                } footer: {
                    Text("CSS is automatically processed to add !important to all declarations.")
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Style", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 550)
        .onAppear {
            loadStyle()
            focusedField = .name
        }
        .confirmationDialog(
            "Delete Style?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                if let style {
                    userStyleManager.delete(style)
                }
                onDismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func loadStyle() {
        guard let style else { return }

        name = style.name
        css = style.css
        isGlobal = style.isGlobal
        domainPatterns = style.domainPatterns.joined(separator: "\n")
    }

    private func saveStyle() {
        let patterns = domainPatterns
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let existingStyle = style {
            existingStyle.name = name
            existingStyle.css = css
            existingStyle.isGlobal = isGlobal
            existingStyle.domainPatterns = patterns
            userStyleManager.update(existingStyle)
        } else {
            let newStyle = UserStyle(
                name: name,
                css: css,
                domainPatterns: patterns,
                isGlobal: isGlobal,
            )
            userStyleManager.add(newStyle)
        }

        onDismiss()
    }
}

// MARK: - UTType Extensions

extension UTType {
    static var css: UTType {
        UTType(filenameExtension: "css") ?? .plainText
    }
}
