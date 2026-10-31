# Delete candidates

Looks dead; scope or origin unverified.

## `Refrax/Core/Agent/AgentChatClientProtocol.swift` + `AgentChatManager.swift` + `AgentChatInputView.swift` — HTTP endpoint / large-attachment scaffolding
- **What**: `isHTTPEndpointAvailable`, `httpEndpointError`, `checkHTTPEndpointAvailability()`, `enableHTTPEndpoint()` on the protocol and manager, `pendingAttachmentsRequireHTTP`, and the input view's HTTP warning state
- **Looks dead because**: leftovers of the removed WebSocket gateway; every client uses the protocol defaults (always available, no error)
- **Not deleted because**: the input view still renders a warning path wired to it, and removing it touches UI that needs a visual check
- **To confirm**: `rg 'HTTPEndpoint|RequireHTTP' Refrax`, then delete and check the chat input in the running app
- **Found**: 2026-09-25

## `Refrax/Core/Agent/AgentChatManager.swift` — `displayMessages` gateway filters
- **What**: the HEARTBEAT/`System: [`/`GatewayRestart:`/`ToolResult:` filters and `isLikelyToolOutput(_:)`
- **Looks dead because**: no current client emits those prefixes; they filtered the removed gateway's transcript
- **Not deleted because**: `isLikelyToolOutput` can also hide a legitimate reply that happens to look like shell output; removing it changes what users see
- **To confirm**: replace `displayMessages` with `messages.filter { $0.role != .system && !$0.isEmpty }` and review a few chats
- **Found**: 2026-09-25

## `Refrax/Core/Agent/ConversationStore.swift:44-70` — `append(sessionId:message:)`, `listSessions()`
- **What**: two static functions
- **Looks dead because**: no callers in the repo
- **Not deleted because**: the survey flagged them alongside larger work; trivial to remove in the same pass as the items above
- **To confirm**: `rg 'ConversationStore\.(append|listSessions)'`
- **Found**: 2026-09-25

## `Refrax/Core/Models/BrowserSettings.swift:505` — `agentEnabled`
- **What**: a persisted, CloudKit-synced setting
- **Looks dead because**: written and synced but never read
- **Not deleted because**: removing a stored `@Model` property is a schema change
- **To confirm**: decide whether agent chat needs an off switch; wire it or remove it with a schema migration
- **Found**: 2026-09-25

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

## `Refrax/Core/Managers/Tabs/BrowserState.swift:243` — `isContentBlockingReady`
- **What**: a flag set once Shields has started, reported through the API's state query
- **Looks dead because**: nothing gates on it; page loads wait on `ShieldsStore.waitUntilReady(timeout:)`, which `ShieldsStore.isReady` answers
- **Not deleted because**: `RefraxAPI` exposes it to API clients (`APIQuery.isContentBlockingReady`), which may read it
- **To confirm**: check API clients (the MCP/agent side) for `isContentBlockingReady`, or ask Kiri; if one reads it, point it at `shields.isReady`
- **Found**: 2026-10-31

## `Refrax/Core/Extensions/Blocking/ShieldsWebKit.swift` — legacy per-list rule list removal
- **What**: `isLegacyPerListIdentifier(_:)`, the `ShieldsRemovedPerListRuleLists` defaults flag, and their branch in `removeStaleLists()`
- **Looks dead because**: it runs once per install, to delete the `<list id>-<n>` rule lists the pre-Shields compiler left in WebKit's store
- **Not deleted because**: users updating from a pre-Shields build still have those lists (tens of MB each) until it has run once
- **To confirm**: once every supported update path starts from a Shields build (a release or two after Shields ships), delete the three pieces and their test
- **Found**: 2026-10-31
