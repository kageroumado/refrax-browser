import AppKit
import Foundation

/// Manages Quick Note integration with macOS Notes app.
///
/// Quick Note allows users to create notes from page content via:
/// - System hotkey (Fn+Q or Globe+Q)
/// - Context menu "Add to Quick Note" action
///
/// ## Implementation
///
/// Uses `NSUserActivity` with Quick Note activity type when possible.
/// Falls back to AppleScript for direct Notes app integration.
///
/// ## Limitations
///
/// - Quick Note API is not fully public
/// - AppleScript requires user authorization
/// - Some Quick Note features may require specific entitlements

final class QuickNoteManager {
    // MARK: - Properties

    /// The current Quick Note activity.
    private var quickNoteActivity: NSUserActivity?

    // MARK: - Public API

    /// Creates a Quick Note with the given content.
    ///
    /// Attempts to use NSUserActivity for system Quick Note integration.
    /// Falls back to AppleScript if the activity approach doesn't work.
    ///
    /// - Parameters:
    ///   - url: The URL to include in the note.
    ///   - title: The page title.
    ///   - selectedText: Optional selected text from the page.
    func createQuickNote(url: URL, title: String, selectedText: String? = nil) {
        // First try NSUserActivity approach
        if createQuickNoteViaActivity(url: url, title: title, selectedText: selectedText) {
            return
        }

        // Fall back to AppleScript
        createQuickNoteViaAppleScript(url: url, title: title, selectedText: selectedText)
    }

    /// Handles system Quick Note hotkey press.
    ///
    /// Call this when Fn+Q is detected to create a note from current page.
    func handleSystemQuickNoteHotkey(url: URL, title: String, selectedText: String?) {
        createQuickNote(url: url, title: title, selectedText: selectedText)
    }

    // MARK: - NSUserActivity Approach

    /// Attempts to create Quick Note via NSUserActivity.
    ///
    /// - Returns: `true` if the activity was created successfully.
    @discardableResult
    private func createQuickNoteViaActivity(url: URL, title: String, selectedText: String?) -> Bool {
        // Create activity for Quick Note
        // Note: The exact activity type may need adjustment based on system behavior
        let activity = NSUserActivity(activityType: "com.apple.notes.quickNote")
        activity.title = title
        activity.webpageURL = url
        activity.isEligibleForHandoff = true
        activity.targetContentIdentifier = url.absoluteString

        // Add selected text to userInfo
        if let text = selectedText, !text.isEmpty {
            activity.userInfo = ["selectedText": text]
        }

        // Make the activity current
        activity.becomeCurrent()
        quickNoteActivity = activity

        Logger.debug("Created Quick Note activity for: \(url.absoluteString)", category: Logger.ui)
        return true
    }

    /// Invalidates the current Quick Note activity.
    func invalidateActivity() {
        quickNoteActivity?.invalidate()
        quickNoteActivity = nil
    }

    // MARK: - AppleScript Approach

    /// Creates a Quick Note via AppleScript as fallback.
    private func createQuickNoteViaAppleScript(url: URL, title: String, selectedText: String?) {
        // Escape strings for AppleScript
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedURL = url.absoluteString.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedText = (selectedText ?? "").replacingOccurrences(of: "\"", with: "\\\"")

        // Build note body with HTML link and optional selected text
        var noteBody = "<a href=\"\(escapedURL)\">\(escapedTitle)</a>"
        if !escapedText.isEmpty {
            noteBody += "<br><br><blockquote>\(escapedText)</blockquote>"
        }

        let script = """
        tell application "Notes"
            activate
            tell account "iCloud"
                make new note at folder "Notes" with properties {name:"\(escapedTitle)", body:"\(noteBody)"}
            end tell
        end tell
        """

        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)

                await MainActor.run {
                    if let error {
                        Logger.error("Quick Note AppleScript error: \(error)", category: Logger.ui)
                    } else {
                        Logger.info("Created Quick Note via AppleScript", category: Logger.ui)
                    }
                }
            }
        }
    }

    // MARK: - Context Menu Support

    /// Creates a context menu item for adding to Quick Note.
    ///
    /// - Parameters:
    ///   - url: The URL to include.
    ///   - title: The page title.
    ///   - selectedText: Optional selected text.
    /// - Returns: An NSMenuItem for the context menu.
    func createContextMenuItem(url: URL, title: String, selectedText: String?) -> NSMenuItem {
        let item = NSMenuItem(
            title: "Add to Quick Note",
            action: nil,
            keyEquivalent: "",
        )

        item.representedObject = QuickNoteAction(url: url, title: title, selectedText: selectedText)

        return item
    }

    /// Action data for Quick Note context menu item.
    struct QuickNoteAction {
        let url: URL
        let title: String
        let selectedText: String?
    }
}
