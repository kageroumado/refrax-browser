# Refrax engine contract

**Version 1.0.** How a rendering engine plugs into Refrax. Refrax is the browser: windows,
tabs, spaces, history, bookmarks, passwords, extensions as installed artifacts, content-blocking
lists, user scripts, settings. An engine renders pages and reports what happens in them. System
WebKit is built in; every other engine is a separately installed bundle that speaks this contract.

The Swift source of truth for every message is `Refrax/Core/Engines/Contract/`. This document
describes the same schema for engine authors, and the binary interface in `SDK/RFXEngine.h`.

## 1. Principles

1. **Events out, commands in.** An engine never exposes live objects to Refrax except the
   page's view. Everything else is a message: *events* describe what happened, *commands* ask for
   something to happen, *requests* ask Refrax to decide, *policy* configures the engine.
2. **Refrax is the source of truth** for browser data. Engines don't keep history, bookmarks,
   passwords, extension installs, or blocking lists of their own; they receive what they need.
3. **Engines are untrusted input.** Refrax size-caps, decodes, and validates every message
   (§6). A malformed message is dropped; a stream of them closes the page.
4. **Facts, once.** Emit an event when something changes, not on a timer, and not twice.

## 2. Engine bundles

An engine is a loadable bundle named `<Name>.engine`, installed at

```
~/Library/Application Support/<Refrax bundle id>/Engines/<engine id>/<Name>.engine
```

`Contents/Info.plist` describes the engine; Refrax reads it without running any engine code:

| Key | Type | Meaning |
|---|---|---|
| `CFBundleIdentifier` | string | Engine ID, reverse-DNS (`website.refrax.engine.chromium`). `system.webkit` is reserved. |
| `CFBundleShortVersionString` | string | Version of the engine bundle |
| `NSPrincipalClass` | string | Class conforming to `RFXEngineHost` |
| `RFXEngineContractVersion` | string | Contract version implemented, `"1.0"` |
| `RFXEngineDisplayName` | string | Name in Settings → Engines |
| `RFXEngineVersion` | string | Version of the rendering engine, e.g. `"Chromium 155.0.8059.12"` |
| `RFXEngineVendor` | string | Who built it |
| `RFXEngineCapabilities` | [string] | §5 |
| `RFXEngineOutOfProcess` | bool | Whether pages render outside Refrax's process |

Before loading, Refrax verifies the bundle's code signature (strict, nested code included)
against a requirement: Refrax's own Team ID for first-party engines, or the identity the user
pinned when trusting a third-party engine. Loading then instantiates the principal class.

**Versioning.** A major version changes the meaning of an existing message; a minor version only
adds messages or optional fields. Refrax loads an engine when the majors match and the engine's
minor is not newer than Refrax's. Engines must ignore unknown optional fields; Refrax does the same.

## 3. Lifecycle

```
Refrax                                   Engine
  │  init (principal class)                 │
  │  startWithConfiguration(json) ─────────▶│  start; call completion once
  │  makePageWithSpec(json) ───────────────▶│  → id<RFXEnginePage>
  │  page.view (re-parented into a window)  │
  │◀──────── didEmitEvent / didRequest ─────│  (main thread)
  │  performCommand / evaluateScript ──────▶│
  │  applyPolicy(json) ────────────────────▶│  applies to every page, now and later
  │  page.close ───────────────────────────▶│  no callbacks after this
  │  shutdown ─────────────────────────────▶│  once, at quit or before an update
```

All calls happen on the main thread; all delegate callbacks must be delivered on the main
thread. An out-of-process engine does its IPC behind these calls. An engine whose processes die
calls `engineHostDidTerminateWithReason:`; Refrax marks its pages crashed and may restart it.

### Configuration

```json
{ "storageDirectory": "file:///…/EngineData/<engine id>/",
  "logFile": "file:///…/EngineData/<engine id>.log",
  "languages": ["en-US", "fr-FR"] }
```

The engine keeps all persistent state inside `storageDirectory` and nowhere else.

### Page spec and profiles

```json
{ "id": "6F1C…UUID", "profile": {"shared": {}}, "initialURL": "https://example.com/" }
```

`profile` partitions storage per Refrax space: `{"shared":{}}`, `{"isolated":{"id":"<uuid>"}}`
(persistent, separate cookies and storage), or `{"ephemeral":{"id":"<uuid>"}}` (in memory,
discarded with the space). `removeProfile` deletes everything stored for one.

## 4. Messages

Every message is a JSON object with one key naming the case; its value holds the named fields.
Cases without fields have an empty object: `{"goBack":{}}`. URLs are strings, dates are seconds
since 1970, optional fields may be omitted or `null`.

### 4.1 Page events (engine → Refrax)

| Case | Fields | When |
|---|---|---|
| `navigationStarted` | `url` | A main-frame navigation began (provisional) |
| `navigationRedirected` | `url` | The provisional navigation was redirected |
| `navigationCommitted` | `url`, `isBackForward` | The page now shows `url` (new document) |
| `sameDocumentNavigation` | `url` | URL changed without a new document (fragment, `pushState`) |
| `navigationFinished` | `url`, `statusCode?` | Main frame finished loading |
| `navigationFailed` | `failure` | See below |
| `titleChanged` | `title` | |
| `progressChanged` | `progress` | 0…1 |
| `loadingChanged` | `isLoading` | |
| `backForwardChanged` | `canGoBack`, `canGoForward` | |
| `securityChanged` | `security`: `secure` \| `mixedContent` \| `insecure` \| `notApplicable` | After commit, when known |
| `faviconsChanged` | `urls` | Candidate icon URLs; Refrax fetches and caches |
| `themeColorChanged` | `color?` | `<meta name=theme-color>` |
| `topEdgeColorChanged` | `color?` | Color along the page's top edge (chrome tint) |
| `hoveredLinkChanged` | `url?` | Link under the pointer; `null` when it leaves |
| `zoomChanged` | `factor` | 1.0 = 100% |
| `mediaChanged` | `media`: `isPlayingAudio`, `isAudioMuted`, `camera`, `microphone`, `screen` (`none`\|`active`\|`muted`) | |
| `fullscreenChanged` | `state`: `none` \| `entering` \| `active` \| `exiting` | Element fullscreen |
| `rendererHealthChanged` | `health`: `{"running":{}}` \| `{"unresponsive":{"since":<date>}}` \| `{"terminated":{"reason":…}}` \| `{"suspended":{}}` | Reasons: `crashed`, `exceededMemoryLimit`, `exceededCPULimit`, `requestedByBrowser`, `unknown` |

`failure` = `{ "kind", "url?", "isProvisional", "engineCode", "description" }` where `kind` is one
of `cancelled`, `cannotFindHost`, `cannotConnectToHost`, `notConnectedToInternet`,
`connectionLost`, `timedOut`, `certificateInvalid`, `httpError`, `blockedByPolicy`, `other`.
`engineCode` is the engine's native code, for diagnostics only.

Colors are `{ "red", "green", "blue", "alpha" }`, each 0…1.

### 4.2 Page commands (Refrax → engine)

| Case | Fields |
|---|---|
| `load` | `request`: `{ "url", "headers": {…}, "referrer?" }` |
| `goBack`, `goForward`, `stopLoading`, `stopFinding`, `focus` | — |
| `reload` | `fromOrigin` (bypass caches) |
| `setZoom` | `factor` |
| `setAudioMuted` | `muted` |
| `setMediaSuspended` | `suspended` |
| `find` | `query`: `{ "text", "forward", "matchCase", "findNext" }` |
| `setVisibility` | `visibility`: `visible` \| `hidden` (throttle when hidden) |
| `devTools` | `command`: `{"show":{}}` \| `{"hide":{}}` \| `{"showConsole":{}}` \| `{"toggleElementSelection":{}}` |
| `terminateRenderer` | — (watchdog; answer with `rendererHealthChanged` → `requestedByBrowser`) |

### 4.3 Requests (engine → Refrax, answered once)

| Case | Fields | Answers |
|---|---|---|
| `openURL` | `url`, `disposition` (`currentTab`\|`foregroundTab`\|`backgroundTab`\|`popup`\|`newWindow`), `userGesture` | `{"handled":{}}` — Refrax opens it |
| `permission` | `kind` (`camera`, `microphone`, `cameraAndMicrophone`, `geolocation`, `notifications`, `screenCapture`, `clipboardRead`), `origin` | `{"allow":{}}` \| `{"deny":{}}` |
| `javaScriptDialog` | `dialog`: `{ "kind": alert\|confirm\|prompt\|beforeUnload, "message", "defaultText?", "origin?" }` | `{"confirm":{"text":…?}}` \| `{"cancel":{}}` |
| `download` | `url`, `suggestedFilename`, `mimeType?` | `{"saveTo":{"url":"file:///…"}}` \| `{"cancel":{}}` |

Refrax never lets an engine choose where files land: the answer to `download` is the destination.
Until an answer arrives the engine waits; if the page closes first, the engine cancels.

### 4.4 Scripts

`evaluateScript` takes `{ "source", "world": {"page":{}} | {"isolated":{"name":…}}, "userGesture" }`
and completes with the result as a plain JSON value (`42`, `"x"`, `{"a":[true,null]}`). Scripts
must not be given a synthetic user gesture unless `userGesture` is true.

Scripts Refrax injects (policy `scripts`, §4.5) may post messages on the channels they were
granted; the engine delivers them with `didReceiveScriptMessage`:
`{ "channel", "body": <JSON>, "frameURL?", "isMainFrame" }`. Posting to a channel the script was
not granted is dropped by the engine. No channel is ever reachable from page-world scripts.

### 4.5 Policy (Refrax → engine)

| Case | Fields |
|---|---|
| `contentBlocking` | `policy`: `{ "isEnabled", "lists": [{ "id", "contents" }], "allowlistedHosts": [...] }` — lists in Adblock Plus / uBlock syntax |
| `scripts` | `scripts`: `[{ "id", "source", "injectionTime": documentStart\|documentEnd, "world", "mainFrameOnly", "matches", "excludes", "channels" }]` — replaces the previous set |
| `extensions` | `extensions`: `[{ "id", "directory", "grantedPermissions", "grantedHostPatterns", "isEnabled" }]` — unpacked, read-only |
| `siteSettings` | `rules`: `[{ "host", "javaScriptEnabled?", "zoom?", "userAgent?", "contentBlockingEnabled?" }]` |

Each update replaces that category's previous state. Engines apply policy to existing and future
pages and never fetch, update, or persist these artifacts themselves.

## 5. Capabilities

Declared in Info.plist; the browser hides or disables features an engine doesn't declare.
`javaScriptEvaluation`, `findInPage`, `zoom`, `snapshots`, `devTools`, `downloads`,
`contentBlocking`, `userScripts`, `webExtensions`, `pictureInPicture`, `mediaCapture`,
`readerMode`, `agentPerception`, `autoFill`, `processInfo`, `rendererControl`.

## 6. Security requirements

Refrax enforces these on its side; engines must not rely on them being absent.

- Messages larger than 256 KiB are rejected; strings are capped at 8 KiB; numbers are clamped
  to their documented ranges.
- URLs in events and requests must use `http`, `https`, `file`, `about`, `data`, `blob`,
  `chrome-extension`, or `refrax`. Anything else rejects the message.
- A page that sends 32 rejected messages is closed.
- Engines must not expose any privileged interface (Refrax APIs, native messaging, IPC to the
  browser) to web content. Refrax's own UI is native; nothing in Refrax is reachable from a
  page's JavaScript except the granted channels of Refrax-injected isolated-world scripts.
- Engines receive no Refrax credentials, keychain access, or history. Autofill values are sent
  one field at a time after the user chooses them.
- Out-of-process engines keep their renderer sandbox enabled.

## 7. Reference implementations

- **System WebKit**: built into Refrax (in-process).
- **Chromium (CEF)**: `Engines/Chromium/` — in-process interim engine, `Scripts/build-chromium-engine.sh`.
- **Chromium (out-of-process host)**: planned. It runs Chromium's browser process as its own app and shows pages through remote layers; this contract does not change.
