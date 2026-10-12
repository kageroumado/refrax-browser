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
