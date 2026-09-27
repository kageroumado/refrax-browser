# Refrax engine contract

**Version 1.2.** How a rendering engine plugs into Refrax. Refrax is the browser: windows,
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
   passwords, extension installs, blocking lists, or keychain items of their own; they receive
   what they need.
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
| `RFXEngineContractVersion` | string | Contract version implemented, `"1.2"` |
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
discarded with the space). `removeProfile` deletes everything stored for one and completes when
the data is gone; Refrax also uses it to clear a space it keeps, so pages made in that profile
afterwards work as in a new one.

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
| `urlChanged` | `url` | The visible URL changed: a navigation began showing its destination, a commit, or a fragment / `pushState` change |
| `navigationFinished` | `url`, `statusCode?` | Main frame finished loading |
| `navigationFailed` | `failure` | See below |
| `titleChanged` | `title` | |
| `progressChanged` | `progress` | 0…1 |
| `loadingChanged` | `isLoading` | True from a main-frame navigation to a new document until that document finishes loading or the navigation ends without one. Subframe loads and same-document navigations leave it unchanged |
| `backForwardChanged` | `canGoBack`, `canGoForward` | |
| `securityChanged` | `security`: `secure` \| `mixedContent` \| `insecure` \| `notApplicable` | After commit, when known |
| `faviconsChanged` | `urls` | Candidate icon URLs; Refrax fetches and caches |
| `themeColorChanged` | `color?` | `<meta name=theme-color>` |
| `topEdgeColorChanged` | `color?` | Color along the page's top edge (chrome tint) |
| `hoveredLinkChanged` | `url?` | Link under the pointer; `null` when it leaves |
| `zoomChanged` | `factor` | 1.0 = 100% |
| `mediaChanged` | `media`: `isPlayingAudio`, `isAudioMuted`, `camera`, `microphone`, `screen` (`none`\|`active`\|`muted`) | |
| `fullscreenChanged` | `state`: `none` \| `entering` \| `active` \| `exiting` | Element fullscreen |
| `notificationShown` | `notification`: `{ "id", "origin", "title", "body", "tag?", "iconURL?", "isSilent" }` | The page called `new Notification()` for an origin Refrax allowed. Engines declaring `notifications` only; service worker notifications are engine events (§4.6) |
| `notificationClosed` | `id` | The page closed a notification it showed |
| `rendererHealthChanged` | `health`: `{"running":{}}` \| `{"unresponsive":{"since":<date>}}` \| `{"terminated":{"reason":…}}` \| `{"suspended":{}}` | Reasons: `crashed`, `sharedProcessCrashed`, `exceededMemoryLimit`, `exceededCPULimit`, `requestedByBrowser`, `unknown` |

`failure` = `{ "kind", "url?", "isProvisional", "engineCode", "description" }` where `kind` is one
of `cancelled`, `cannotFindHost`, `cannotConnectToHost`, `notConnectedToInternet`,
`connectionLost`, `timedOut`, `certificateInvalid`, `httpError`, `blockedByPolicy`, `other`.
`engineCode` is the engine's native code, for diagnostics only.

Colors are `{ "red", "green", "blue", "alpha" }`, each 0…1.

### 4.2 Page commands (Refrax → engine)

| Case | Fields |
|---|---|
| `load` | `request`: `{ "url", "headers": {…}, "referrer?" }` |
| `goBack`, `goForward`, `stopLoading`, `stopFinding` | — |
| `focus` | — (keystrokes go to the page's content from then on) |
| `reload` | `fromOrigin` (bypass caches) |
| `setZoom` | `factor` — this page's zoom, kept across its navigations; engines keep no zoom of their own (per site or saved) |
| `setAudioMuted` | `muted` |
| `setMediaSuspended` | `suspended` |
| `find` | `query`: `{ "text", "forward", "matchCase", "findNext" }` |
| `setVisibility` | `visibility`: `visible` \| `hidden` (throttle when hidden) |
| `devTools` | `command`: `{"show":{}}` \| `{"hide":{}}` \| `{"showConsole":{}}` \| `{"toggleElementSelection":{}}` |
| `terminateRenderer` | — (watchdog; answer with `rendererHealthChanged` → `requestedByBrowser`) |
| `notificationClicked`, `notificationClosed` | `id` — the user clicked or dismissed the notification; fire its `click` / `close` event |

### 4.3 Requests (engine → Refrax, answered once)

| Case | Fields | Answers |
|---|---|---|
| `openURL` | `url`, `disposition` (`currentTab`\|`foregroundTab`\|`backgroundTab`\|`popup`\|`newWindow`), `userGesture`, `isNewWindowRequest?` (1.2) | `{"handled":{}}` — Refrax opens it |
| `navigation` (1.2) | `url`, `kind` (`link`\|`formSubmission`\|`backForward`\|`reload`\|`other`), `initiatorOrigin?` | `{"allow":{}}` \| `{"cancel":{}}` |
| `permission` | `kind` (`camera`, `microphone`, `cameraAndMicrophone`, `geolocation`, `notifications`, `screenCapture`, `clipboardRead`), `origin` | `{"allow":{}}` \| `{"deny":{}}` |
| `javaScriptDialog` | `dialog`: `{ "kind": alert\|confirm\|prompt\|beforeUnload, "message", "defaultText?", "origin?" }` | `{"confirm":{"text":…?}}` \| `{"cancel":{}}` |
| `download` | `id`, `url`, `suggestedFilename`, `mimeType?`, `totalBytes?` | `{"saveTo":{"url":"file:///…"}}` \| `{"cancel":{}}` |

`navigation` is asked for every main-frame navigation to an `http`, `https`, `file`, `data`, `blob` or
`refrax` URL before its first request, including the ones Refrax starts; the navigation waits
for the answer and goes ahead only on `allow`. Refrax answers `cancel` when it takes the URL
somewhere itself: it loads a cleaned URL with a new `load`, shows a preview, opens a tab, or hands
the URL to another app. Redirects go ahead without asking. `kind` is `link` only for a link the
user activated in the page (a script's location change is `other`). `initiatorOrigin` is the
serialized origin of the document that started the navigation (`"null"` when opaque), omitted
when Refrax or the user started it (address bar, reload, back/forward).

`openURL`'s `isNewWindowRequest` is true when the page asked for a new browsing context
(`target=_blank`, `window.open`) and false when the user's modifier click or middle button did.
Refrax decides where the URL goes: a new tab, a preview, or nowhere for a popup the site's
settings block.

Engines never show their own dialog or permission UI. Refrax answers `permission` from the
site's settings or asks the user, and shows `javaScriptDialog` in the page's own pane, labeled
with `origin`; a question stays with its page, so a background page's dialog waits until the page
is shown. A permission Refrax has no `kind` for is denied by the engine. Dialog text over 2,000
characters is truncated by the engine (strings are capped, §6). A committed navigation dismisses
pending questions, answering them `cancel` / `deny`; the engine answers a page's pending dialogs
`cancel` itself when Refrax starts a navigation (`load`, `goBack`, `goForward`, `reload`), since a
dialog holds its renderer until answered. An answer to a question that is no longer pending is
ignored.

Refrax never lets an engine choose where files land: the answer to `download` is the destination.
Until an answer arrives the engine waits; if the page closes first, the engine cancels.
The engine then writes the file itself, since only it holds the page's session (cookies, `blob:`
data, POST bodies), and reports `downloadProgressed { id, receivedBytes, totalBytes? }`, then
exactly one of `downloadFinished { id }` or `downloadFailed { id, reason }`. `cancelDownload { id }`
stops it. Refrax renames the partial file, sets its quarantine attributes, and shows the download;
a download still running when its page closes is reported failed.

### 4.4 Scripts

`evaluateScript` takes `{ "source", "world": {"page":{}} | {"isolated":{"name":…}}, "userGesture" }`
and completes with the result as a plain JSON value (`42`, `"x"`, `{"a":[true,null]}`). Scripts
must not be given a synthetic user gesture unless `userGesture` is true. `undefined` is `null`;
integral numbers carry no fraction; a promise settles before the call completes; a thrown value
fails the call with its message (a syntax error's message names `SyntaxError`). Every call
completes exactly once, with an error if the page closes or its engine dies first. Injected
scripts' `matches` and `excludes` are WebExtensions match patterns (empty `matches`: every page).

Scripts Refrax injects (policy `scripts`, §4.5) post messages with the WebKit call shape, in the
world they run in:

```js
window.webkit.messageHandlers.<channel>.postMessage(body)
```

Engines provide exactly that object in each world, containing only the channels granted to that
world's scripts, and deliver each message with `didReceiveScriptMessage`:
`{ "channel", "world", "body": <JSON>, "frameURL?", "isMainFrame" }`, where `world` is the world the
posting script runs in as the engine knows it — never a value taken from the message. A message on a channel the world was
not granted is dropped by the engine.

`postMessage` returns a promise. Refrax calls the delivery's `reply` exactly once with a
`ScriptReply` — `{"value":{"value":<JSON>}}` resolves the promise with the value (`null` for
one-way channels, once the handler has run); `{"error":{"message"}}` rejects it with an `Error`.
The engine settles the promise in the execution context that made the call; if that context is
gone (navigation, frame removed), the reply is discarded. Channels granted to isolated-world scripts must not be
reachable from page-world scripts. (Some of Refrax's own scripts run in the page world because
they observe page APIs; their channels are reachable by the page and their handlers treat every
message as untrusted.)

### 4.5 Policy (Refrax → engine)

| Case | Fields |
|---|---|
| `contentBlocking` | `policy`: `{ "isEnabled", "lists": [{ "id", "contents" }], "allowlistedHosts": [...] }` — lists in Adblock Plus / uBlock syntax |
| `scripts` | `scripts`: `[{ "id", "source", "injectionTime": documentStart\|documentEnd, "world", "mainFrameOnly", "matches", "excludes", "channels" }]` — replaces the previous set |
| `extensions` | `extensions`: `[{ "id", "directory", "grantedPermissions", "grantedHostPatterns", "isEnabled" }]` — unpacked, read-only |
| `siteSettings` (1.2) | `policy`: `{ "javaScriptEnabled", "rules": [{ "host", "javaScriptEnabled?", "contentBlockingEnabled?", "autoplayWithSound?" }] }` |
| `notifications` | `policy`: `{ "granted": [origin], "denied": [origin], "asksByDefault" }` — every notification decision Refrax holds |

Each update replaces that category's previous state. Engines apply policy to existing and future
pages and never fetch, update, or persist these artifacts themselves.

`siteSettings` is Refrax's per-site settings an engine enforces itself. `javaScriptEnabled` is
the default; a rule's `host` is a registrable domain and covers its subdomains, and an absent
field leaves the default. `contentBlockingEnabled: false` spares the site as `allowlistedHosts`
does; `autoplayWithSound: true` lets its media play with sound before the user interacts, where
the default lets only muted media autoplay. Changes take effect on the next load. Zoom (`setZoom`)
and permissions (`permission` requests) are per page and per request instead. Engines block no
popups of their own: every new window a page asks for reaches Refrax as `openURL`, with
`userGesture`, and Refrax decides.

`notifications` is the only source of notification permission in the engine: `Notification.permission`
and permission queries read it (`granted`, `denied`, or for other origins `default` when
`asksByDefault`, else `denied`), a changed policy reaches open pages at once, and an origin in
neither list asks with a `permission` request. Engines never store a notification decision of
their own, including the answer to that request: Refrax sends the updated policy before it
answers. Origins are serialized as `scheme://host[:port]`.

### 4.6 Engine events, commands and requests

What happens outside any page travels between the engine and Refrax directly
(`engineHost:didEmitEvent:`, `performCommand:` and `engineHost:didRequest:reply:` in
`RFXEngine.h`), in the same JSON shape.

| Event (engine → Refrax) | Fields | When |
|---|---|---|
| `notificationShown` | `profile` (the page spec's profile), `notification` (as in §4.1) | A service worker showed a notification, or a page did and the engine can't name the page |
| `notificationClosed` | `id` | The worker or page closed it |

| Command (Refrax → engine) | Fields |
|---|---|
| `notificationClicked`, `notificationClosed` | `id` — the user clicked or dismissed the notification; fire its `notificationclick` / `notificationclose` (or `click` / `close`) event |

| Request (engine → Refrax, answered once) | Fields | Answers |
|---|---|---|
| `secret` | `name`: `[A-Za-z0-9._-]`, 1–64 characters | `{"secret":{"value":"<base64>"}}` \| `{"unavailable":{}}` |

`secret` is how an engine gets key material, such as the key it encrypts cookies with. Refrax
keeps each engine's secrets in its own keychain, one item per engine id and name, and creates a
secret on the first request for it: 32 random bytes, the same on every later request. An engine
never creates keychain items: the access list of an item belongs to the code signature that
created it, so an engine update signed differently would stop at a keychain prompt no one sees.
`unavailable` means the keychain can't be read now (it is locked); the engine still loads pages.
Refrax answers every `secret` request, including one sent before `startWithConfiguration:`
completes, since an engine may need its secrets to finish starting.

Notification ids are unique across the engine's profiles, so an id alone names the notification in
either direction.

## 5. Capabilities

Declared in Info.plist; the browser hides or disables features an engine doesn't declare.
`javaScriptEvaluation`, `findInPage`, `zoom`, `snapshots`, `devTools`, `downloads`,
`contentBlocking`, `userScripts`, `webExtensions`, `pictureInPicture`, `mediaCapture`,
`readerMode`, `agentPerception`, `autoFill`, `processInfo`, `rendererControl`, `notifications`.

`notifications`: Refrax answers `permission` requests of kind `notifications` from its per-origin
store, pushes the `notifications` policy, and delivers `notificationShown` (page or engine event)
through Notification Center. Engines without it get `deny`, so pages never believe they can notify
when nothing would appear.

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

## 7. Conformance

`Engines/Conformance` checks an engine bundle against this contract by driving it through
`RFXEngine.h` against fixtures it serves on loopback: `forge conformance <name>` for the
Chromium engine, or build it with `swiftc` and run `engine-conformance <X.engine>` for any
other. The input tests need the runner to be the active app, which macOS grants when it is
launched from the frontmost app; otherwise they are skipped.

## 8. Reference implementations

- **System WebKit**: built into Refrax (in-process).
- **Chromium (CEF)**: `Engines/Chromium/` — in-process interim engine, `Scripts/build-chromium-engine.sh`.
- **Chromium (out-of-process host)**: `Engines/Chromium/refrax/`, built by `Scripts/forge/forge`. It runs Chromium's browser process as its own app and shows pages through remote layers.
