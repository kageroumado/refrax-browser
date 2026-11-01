import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The types a drop on an island reads, and the identity a dragged row carries.
nonisolated enum IslandPasteboard {
    /// The dragged tab's identity, as a UUID string.
    static let tabIDs = NSPasteboard.PasteboardType("com.refrax.tab-id")
    static let tabIDType = UTType(importedAs: tabIDs.rawValue)

    /// Every type a drop on an island can bring.
    static let dropTypes: [UTType] = [tabIDType, .fileURL, .url, .plainText]

    /// Reads what `providers`, one per dragged item, bring: a dragged row's identity and
    /// address, a link, a file, or text.
    @MainActor
    static func payload(from providers: [NSItemProvider]) async -> IslandDropPayload {
        var tabIDs: [UUID] = []
        var urls: [URL] = []
        var strings: [String] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(tabIDType.identifier),
               let data = await data(of: tabIDType, from: provider),
               let id = String(data: data, encoding: .utf8).flatMap({ UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
                tabIDs.append(id)
            }
            // A link or a file is read as its URL; text, only when it is nothing else, for the
            // addresses written in it.
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = await url(from: provider) {
                    urls.append(url)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = await text(from: provider) {
                strings.append(text)
            }
        }
        return IslandDropPayload(tabIDs: tabIDs, urls: urls, strings: strings)
    }

    @MainActor
    private static func data(of type: UTType, from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    @MainActor
    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                continuation.resume(returning: (object as? NSURL).map { $0 as URL })
            }
        }
    }

    @MainActor
    private static func text(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString).map { $0 as String })
            }
        }
    }
}

/// Takes links, files, text, and rows dragged from another window onto one island's rows:
/// shows where the drop goes while it is held, and lands it on the row under the pointer.
///
/// A SwiftUI drop target on the island itself, so the drag reaches the island the pointer
/// is over, through the layer's own hit testing, and nothing joins the key-view loop.
struct IslandDropDelegate: DropDelegate {
    let islandID: UUID
    let islands: IslandController

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: IslandPasteboard.dropTypes)
    }

    func dropEntered(info: DropInfo) {
        islands.updateExternalDrop(on: islandID, local: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        islands.updateExternalDrop(on: islandID, local: info.location)
        return DropProposal(operation: info.hasItemsConforming(to: [IslandPasteboard.tabIDType]) ? .move : .copy)
    }

    func dropExited(info _: DropInfo) {
        islands.endExternalDrop()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let target = islands.dropTarget(on: islandID, local: info.location) else {
            islands.endExternalDrop()
            return false
        }
        let providers = info.itemProviders(for: IslandPasteboard.dropTypes)
        let islands = islands
        Task(name: "Read a drop on an island") {
            let payload = await IslandPasteboard.payload(from: providers)
            islands.performDrop(payload, at: target)
        }
        return true
    }
}
