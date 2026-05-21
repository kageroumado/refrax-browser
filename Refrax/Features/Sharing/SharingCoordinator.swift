import AppKit
import Observation

/// Coordinator for presenting the system share sheet.
///
/// This coordinator is injected into the environment and provides a centralized
/// way to trigger sharing functionality from anywhere in the view hierarchy.
///
/// ## Usage
///
/// Access the coordinator through the environment and call `share(items:)`:
///
/// ```swift
/// @Environment(SharingCoordinator.self) private var sharingCoordinator
///
/// Button("Share") {
///     sharingCoordinator.share(items: [url])
/// }
/// ```
///
/// ## Presented From
///
/// The share sheet is presented relative to the current key window.
/// If no window is available, the sharing request is silently ignored.
@Observable
final class SharingCoordinator {
    /// Items currently being shared.
    private(set) var sharingItems: [Any]?

    /// Position where the share sheet should appear (relative to window).
    private(set) var sharePosition: CGPoint?

    /// Presents the system share sheet with the specified items.
    ///
    /// The share sheet appears as a popover near the share button or at
    /// the center of the window if no position is specified.
    ///
    /// - Parameters:
    ///   - items: Items to share (URLs, strings, images, etc.)
    ///   - position: Optional position for the popover anchor (in window coordinates).
    func share(items: [Any], at position: CGPoint? = nil) {
        guard !items.isEmpty else { return }

        sharingItems = items
        sharePosition = position

        presentShareSheet(items: items, at: position)
    }

    /// Presents a URL for sharing.
    ///
    /// Convenience method for sharing a single URL with an optional title.
    ///
    /// - Parameters:
    ///   - url: The URL to share.
    ///   - title: Optional title to include (shown in some sharing destinations).
    ///   - position: Optional position for the popover anchor.
    func shareURL(_ url: URL, title: String? = nil, at position: CGPoint? = nil) {
        var items: [Any] = [url]

        if let title {
            items.insert(title, at: 0)
        }

        share(items: items, at: position)
    }

    /// Dismisses the share sheet if it's currently presented.
    func dismiss() {
        sharingItems = nil
        sharePosition = nil
    }
}

// MARK: - Private

private extension SharingCoordinator {
    func presentShareSheet(items: [Any], at position: CGPoint?) {
        guard let window = NSApp.keyWindow else {
            Logger.warning("Cannot present share sheet: no key window", category: Logger.ui)
            return
        }

        let picker = NSSharingServicePicker(items: items)
        picker.delegate = SharePickerDelegate.shared

        let anchorRect: NSRect
        if let position {
            anchorRect = NSRect(origin: position, size: CGSize(width: 1, height: 1))
        } else {
            let windowCenter = CGPoint(
                x: window.frame.width / 2,
                y: window.frame.height / 2,
            )
            anchorRect = NSRect(origin: windowCenter, size: CGSize(width: 1, height: 1))
        }

        guard let contentView = window.contentView else {
            Logger.warning("Cannot present share sheet: window has no content view", category: Logger.ui)
            return
        }

        picker.show(relativeTo: anchorRect, of: contentView, preferredEdge: .minY)
    }
}

// MARK: - Share Picker Delegate

/// Delegate for customizing share picker behavior.
private final class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    static let shared = SharePickerDelegate()

    func sharingServicePicker(
        _: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService],
    ) -> [NSSharingService] {
        var services = proposedServices

        if let copyLinkService = createCopyLinkService(for: items) {
            services.insert(copyLinkService, at: 0)
        }

        return services
    }

    private func createCopyLinkService(for items: [Any]) -> NSSharingService? {
        guard items.contains(where: { $0 is URL }) else {
            return nil
        }

        let service = NSSharingService(
            title: "Copy Link",
            image: NSImage(systemSymbolName: "link", accessibilityDescription: "Copy Link")!,
            alternateImage: nil,
        ) {
            let urls = items.compactMap { $0 as? URL }
            let urlStrings = urls.map(\.absoluteString).joined(separator: "\n")

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(urlStrings, forType: .string)

            for url in urls {
                pasteboard.setString(url.absoluteString, forType: .URL)
            }
        }

        return service
    }
}
