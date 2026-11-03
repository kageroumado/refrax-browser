# Delete candidates

Looks dead; scope or origin unverified.

## `Refrax/Core/Models/Tabs/TabGroup.swift:51-77`, `Refrax/Core/Models/Tabs/Space.swift:123` — desk-only group and space fields
- **What**: `TabGroup.boardFrameData`/`boardFrame`, `boardAnchorData`/`boardAnchor`, `isMagnet`, `stackSite`, and `Space.stacksBySite`, with their CloudKit record fields in `Core/Sync/Extensions`
- **Looks dead because**: the desk (zones, magnets, site stacks) was retired with the islands; nothing reads them now, only the model and sync code write them
- **Not deleted because**: they are persisted `@Model` properties synced through CloudKit; removing them is a schema change
- **To confirm**: `rg 'boardAnchor|isMagnet|stackSite|stacksBySite|TabGroup.*boardFrame' Refrax`, then remove with a schema migration
- **Found**: 2026-10-23

## `Refrax/Core/Models/Extensions/InstalledExtension.swift:247` — `ExtensionGlobalSettings.installedBundledExtensions`
- **What**: the set of bundled extensions Refrax auto-installed, and its one write in `ExtensionManager.installBundledExtension(from:name:)`
- **Looks dead because**: only the removed first-launch auto-install read it; uBlock Origin now installs on request (`installBundledUBlockOrigin()`)
- **Not deleted because**: it is persisted extension state, and the extensions work in parallel may want it back for another bundled extension
- **To confirm**: `rg installedBundledExtensions Refrax`; if nothing reads it, drop the property and the write
- **Found**: 2026-10-31

## `Refrax/Core/Extensions/Blocking/ShieldsWebKit.swift` — legacy per-list rule list removal
- **What**: `isLegacyPerListIdentifier(_:)`, the `ShieldsRemovedPerListRuleLists` defaults flag, and their branch in `removeStaleLists()`
- **Looks dead because**: it runs once per install, to delete the `<list id>-<n>` rule lists the pre-Shields compiler left in WebKit's store
- **Not deleted because**: users updating from a pre-Shields build still have those lists (tens of MB each) until it has run once
- **To confirm**: once every supported update path starts from a Shields build (a release or two after Shields ships), delete the three pieces and their test
- **Found**: 2026-10-31

## `Refrax/App/RefraxAppDelegate.swift:1082-1116` — `removeRetiredAgentChatData()`
- **What**: the once-per-install cleanup of the retired agent chat, `retiredAgentCredentialServices`, the `website.refrax.migration.removedAgentChat` defaults flag, and its call at line 628
- **Looks dead because**: it is the last code naming the in-browser agent chat, which was removed in v0.34; on an install that has run it once it does nothing
- **Not deleted because**: users updating from a build with the agent chat still have its API keys in their keychain and its conversations in Application Support until it has run once
- **To confirm**: once every supported update path starts from v0.34 or later, delete the three pieces
- **Found**: 2026-11-03
