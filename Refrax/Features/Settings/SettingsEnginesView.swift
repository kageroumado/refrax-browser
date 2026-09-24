import AppKit
import SwiftUI

// MARK: - Engines Settings

/// Installed rendering engines: what each one is, whether it is running, and removal.
struct EnginesSettingsView: View {
    @Environment(EngineRegistry.self) private var registry
    let highlightedItemId: String?

    @State private var pendingRemoval: EngineDescriptor?
    @State private var removalError: String?

    var body: some View {
        Form {
            Section {
                ForEach(registry.descriptors, id: \.id) { descriptor in
                    EngineRow(
                        descriptor: descriptor,
                        isRunning: registry.runningEngines.contains(descriptor.id),
                        bundleURL: registry.bundleURL(for: descriptor.id),
                        onRemove: { pendingRemoval = descriptor },
                    )
                }
            } header: {
                Text("Installed Engines")
            } footer: {
                Text("WebKit renders every page unless a tab is moved to another engine with View → Reload in…. A tab remembers its engine.")
            }
            .highlightable(id: "engines.installed", highlightedItemId: highlightedItemId)

            Section {
                LabeledContent("Location") {
                    Text((registry.enginesDirectory.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: registry.enginesDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([registry.enginesDirectory])
                    }
                    Button("Rescan") {
                        registry.refresh()
                    }
                }
            } header: {
                Text("Engines Folder")
            } footer: {
                Text("Refrax loads an engine only if it is signed by the same developer as Refrax.")
            }
            .highlightable(id: "engines.folder", highlightedItemId: highlightedItemId)
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove \(pendingRemoval?.displayName ?? "engine")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval,
        ) { descriptor in
            Button("Remove Engine and Its Data", role: .destructive) { remove(descriptor, removingData: true) }
            Button("Remove Engine Only") { remove(descriptor, removingData: false) }
            Button("Cancel", role: .cancel) {}
        } message: { descriptor in
            Text("\(descriptor.displayName) moves to the Trash. Tabs that used it open in WebKit. Its data holds cookies and site storage from pages it rendered.")
        }
        .alert("Couldn't Remove Engine", isPresented: Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalError ?? "")
        }
    }

    private func remove(_ descriptor: EngineDescriptor, removingData: Bool) {
        do {
            try registry.uninstall(descriptor.id, removingData: removingData)
        } catch {
            removalError = error.localizedDescription
        }
    }
}

// MARK: - Engine Row

private struct EngineRow: View {
    let descriptor: EngineDescriptor
    let isRunning: Bool
    let bundleURL: URL?
    let onRemove: () -> Void

    private var isBuiltIn: Bool {
        descriptor.id == .systemWebKit
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isBuiltIn ? "safari" : "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(descriptor.displayName)
                        .font(.headline)
                    if isRunning, !isBuiltIn {
                        Text("Running")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(capabilitySummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !isBuiltIn {
                Menu {
                    if let bundleURL {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                        }
                    }
                    Button("Remove…", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        var parts = [descriptor.engineVersion]
        if !descriptor.vendor.isEmpty {
            parts.append(descriptor.vendor)
        }
        parts.append(isBuiltIn ? "Built in" : descriptor.isOutOfProcess ? "Separate process" : "In Refrax's process")
        parts.append("Contract \(descriptor.contractVersion)")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var capabilitySummary: String {
        let names = EngineCapabilities.namesByCapability
            .filter { descriptor.capabilities.contains($0.1) }
            .map(\.0)
        return names.isEmpty ? "Renders pages" : "Supports: " + names.joined(separator: ", ")
    }
}
