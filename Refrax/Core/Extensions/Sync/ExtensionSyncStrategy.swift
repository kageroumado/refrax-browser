import Foundation

// MARK: - Extension Sync Strategy Documentation

// # Extension iCloud Sync - Deferred for MVP
//
// ## Current Status
//
// Extension sync is **deferred** for the MVP release. The extension system stores
// all state locally in `~/Library/Application Support/Refrax/Extensions/state.json`.
//
// ## Why Deferred?
//
// 1. **Complexity**: Cross-device extension sync requires handling:
//    - Merge conflicts when extensions are installed/removed on different devices
//    - Permission state reconciliation (which grants take precedence?)
//    - Extension source availability (what if Chrome Web Store changes?)
//    - Timing coordination (prevent race conditions during sync)
//
// 2. **Storage Limits**: `NSUbiquitousKeyValueStore` has a 1MB total limit and
//    1024 key limit. Extension metadata alone could exceed this for power users
//    with many extensions.
//
// 3. **Security Considerations**: Syncing permission grants across devices
//    requires careful handling - a permission granted on one device may not
//    be appropriate on another (different security contexts, different browsing
//    patterns).
//
// ## Future Implementation Options
//
// ### Option 1: NSUbiquitousKeyValueStore (Simple)
//
// **Pros:**
// - Built-in conflict resolution
// - No server infrastructure needed
// - Automatic background sync
//
// **Cons:**
// - 1MB total storage limit
// - Must serialize all extension state to JSON
// - No fine-grained change tracking
//
// **Best for:** Syncing just the extension list and enabled/disabled state,
// not full settings or permissions.
//
// ### Option 2: CloudKit (Recommended)
//
// **Pros:**
// - Much larger storage capacity
// - Record-level sync with conflict resolution
// - Can sync actual extension files if needed
// - Per-record change tracking
//
// **Cons:**
// - More complex implementation
// - Requires CloudKit container setup
// - Need to handle offline/online transitions
//
// **Best for:** Full extension sync including settings and permissions.
//
// ### Option 3: iCloud Documents
//
// **Pros:**
// - Can store extension archives directly
// - User-visible in iCloud Drive
// - Good for large files
//
// **Cons:**
// - No structured data support
// - Manual conflict resolution needed
// - User might accidentally delete
//
// **Best for:** Backing up extension source files, not state sync.
//
// ## Recommended Future Architecture
//
// ```
// ┌─────────────────────────────────────────────────────────────┐
// │                   ExtensionSyncManager                       │
// ├─────────────────────────────────────────────────────────────┤
// │                                                             │
// │  ┌─────────────────┐     ┌──────────────────────┐          │
// │  │ Local State     │◄───►│ CloudKit Container   │          │
// │  │ (JSON file)     │     │ (CKRecord per ext)   │          │
// │  └─────────────────┘     └──────────────────────┘          │
// │          │                         │                        │
// │          ▼                         ▼                        │
// │  ┌─────────────────┐     ┌──────────────────────┐          │
// │  │ InstalledExt    │     │ CKSubscription       │          │
// │  │ collection      │     │ (push notifications) │          │
// │  └─────────────────┘     └──────────────────────┘          │
// │                                                             │
// └─────────────────────────────────────────────────────────────┘
// ```
//
// ## Sync State Model
//
// When implemented, each extension would track:
//
// ```swift
// struct ExtensionSyncState: Codable {
//     /// CloudKit record ID
//     var recordID: String?
//
//     /// Last known server modification date
//     var serverModificationDate: Date?
//
//     /// Local modification date
//     var localModificationDate: Date
//
//     /// Sync status
//     var syncStatus: SyncStatus
//
//     enum SyncStatus {
//         case synced
//         case pendingUpload
//         case pendingDownload
//         case conflict(serverValue: Data, localValue: Data)
//     }
// }
// ```
//
// ## Conflict Resolution Strategy
//
// 1. **Extension List**: Merge installed lists (union), prefer most recent
//    enabled/disabled state per extension.
//
// 2. **Permissions**: Most recent change wins, with option to prompt user
//    when permission scope differs significantly.
//
// 3. **Settings**: Per-extension, most recent wins. Consider per-setting
//    granularity for complex extensions.
//
// ## Implementation Checklist (Future)
//
// - [ ] Create CloudKit container in App Store Connect
// - [ ] Define CKRecord schema for extensions
// - [ ] Implement `ExtensionSyncManager` actor
// - [ ] Add sync status indicators to UI
// - [ ] Handle initial sync on new device
// - [ ] Implement conflict resolution UI
// - [ ] Add sync toggle in Settings
// - [ ] Test offline scenarios
// - [ ] Test multi-device simultaneous edits

// MARK: - Placeholder Types

/// Placeholder for future sync manager implementation.
///
/// This will be implemented when extension sync is prioritized post-MVP.
enum ExtensionSyncManager {
    /// Current sync is deferred - use local storage only.
    static let isEnabled = false
}

/// Future sync configuration options.
struct ExtensionSyncConfiguration: Sendable, Equatable {
    /// Whether to sync extension list.
    var syncExtensionList: Bool = true

    /// Whether to sync enabled/disabled state.
    var syncEnabledState: Bool = true

    /// Whether to sync permission grants.
    var syncPermissions: Bool = false

    /// Whether to sync per-extension settings.
    var syncSettings: Bool = false
}
