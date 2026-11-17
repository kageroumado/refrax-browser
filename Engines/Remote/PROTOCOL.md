# Remote engine protocol

**Version 1.** How the engine-neutral client (`Engines/Remote/Sources`, the executable of an
out-of-process engine's `.engine` bundle) talks to that engine's host process. The client holds
nothing of any engine: it starts the host, carries the engine contract's JSON
(`Engines/CONTRACT.md`) between the host and Refrax, shows each page through a remote layer
the host names, and forwards input. An engine that renders into a Core Animation context of
its own gets into Refrax by writing a host that speaks this protocol.

## 1. Starting

The bundle's `Info.plist` names the host with `RFXRemoteHostExecutable`, a path relative to the
bundle's `Contents`. Its `NSPrincipalClass` is `RFXRemoteEngine`.

The client makes a socket pair and starts the host with `--wire-fd=<n>`, where `n` is the
host's end. The host inherits that descriptor, `/dev/null` as its input, and the contract's
`logFile` as its output and error; nothing else of Refrax's. The host exits when the socket
closes, and the client reports the engine dead when the socket closes without a `shutdown`.

## 2. Framing

Each message is a JSON object after its length in bytes as a 32-bit unsigned integer, most
significant byte first. The object has one key, the message's name, whose value is an object
holding its fields. A frame longer than 64 MiB closes the connection.

Numbers named `page` are the client's numbers for pages, unique for the life of the engine.
Numbers named `id` pair a message with its answer and are unique for the life of the engine.

## 3. Client → host

| Message | Fields | Meaning |
|---|---|---|
| `start` | `storagePath`, `languages` | The contract's `EngineConfiguration`, with the storage directory as a path. Answered by `started` or `startFailed` |
| `makePage` | `page`, `spec` (the contract's `EnginePageSpec`), `width`, `height`, `scale`, `framesPerSecond` | A new page of that size in points |
| `closePage` | `page` | Nothing more is sent about the page, either way |
| `command` | `page`, `command` (a `PageCommand`) | |
| `evaluate` | `page`, `id`, `request` (a `ScriptRequest`) | Answered by `evaluated` |
| `snapshot` | `page`, `id` | Answered by `snapshotTaken` |
| `answer` | `page`, `id`, `answer` (a `PageRequestAnswer`) | The answer to `request` `id` |
| `geometry` | `page`, `width`, `height`, `scale` | The view's size in points and its backing scale |
| `focusState` | `page`, `focused` | Whether the view is the first responder of the key window |
| `mouse` | `page`, `type`, `x`, `y`, `screenX`, `screenY`, `button`, `buttons`, `modifiers`, and `clickCount` or the wheel fields | §5 |
| `key` | `page`, `id`, `type`, `keyCode`, `characters`, `charactersIgnoringModifiers`, `modifiers`, `repeat`, `commands` | §5. Answered by `keyHandled` or `keyUnhandled` |
| `edit` | `page`, `action`: `selectAll` \| `copy` \| `cut` \| `paste` \| `undo` \| `redo` | A command from Refrax's Edit menu |
| `policy` | `update` (a `PolicyUpdate`) | |
| `scriptReply` | `page`, `id`, `reply` (a `ScriptReply`) | The answer to `scriptMessage` `id`, which settles the script's `postMessage` promise |
| `engineCommand` | `command` (an `EngineCommand`) | |
| `removeProfile` | `id`, `profile` (an `EngineProfileSpec`) | Answered by `profileRemoved` once the data is gone |
| `clipboardText` | `id`, `profile`, `text` | The answer to `clipboardRead` |
| `shutdown` | — | The host closes every page and exits |

## 4. Host → client

| Message | Fields | Meaning |
|---|---|---|
| `started` | — | |
| `startFailed` | `message` | |
| `event` | `page`, `event` (a `PageEvent`) | |
| `request` | `page`, `id`, `request` (a `PageRequestKind`) | Answered by `answer` |
| `evaluated` | `page`, `id`, and `result` (the value as JSON text) or `error` | |
| `scriptMessage` | `page`, `id`, `message` (a `ScriptMessage`) | A script Refrax injected posted on one of its channels. Answered by `scriptReply` |
| `snapshotTaken` | `page`, `id`, and `path`, `width`, `height`, `bytesPerRow` | The frame is in the file at `path`: BGRA, premultiplied alpha, top row first. The client reads and removes it. Without `path`, the page has no frame |
| `layer` | `page`, `contextID` | The Core Animation context the page renders into, shown with a `CALayerHost`; 0 for none |
| `cursor` | `page`, `name` | `Arrow`, `IBeam`, `Hand`, `Crosshair`, `OpenHand`, `Drag`, `DragCopy`, `Disallowed`, `ResizeHorizontal`, `ResizeVertical`, `ResizeColumn`, `ResizeRow` |
| `keyHandled` | `page`, `id` | The page used the key |
| `keyUnhandled` | `page`, `id` | The page left the key alone: Refrax's menus get a key held with Command or Control |
| `clipboardWrite` | `text` | Text for the general pasteboard |
| `clipboardRead` | `id`, `profile` | Answered by `clipboardText` |
| `engineEvent` | `event` (an `EngineEvent`) | |
| `profileRemoved` | `id` | |
| `pageFailed` | `page`, `message` | The page could not be made |
| `terminated` | `reason` | The engine is ending by itself; the socket closes next |

## 5. Input

Positions are in points from the top left of the view (`x`, `y`) and of the primary screen
(`screenX`, `screenY`).

`mouse` `type` is `down`, `up`, `move`, `leave` or `wheel`. `button` is the button a `down` or
`up` is about and `buttons` the ones held, as bits: primary 1, secondary 2, middle 4.
`modifiers` are bits: Shift 1, Control 2, Option 4, Command 8, numeric keypad 16. A `wheel`
carries `deltaX` and `deltaY` in points, positive scrolling the content down or right,
`precise` (a trackpad's pixel deltas, as opposed to a wheel's notches) and `phase`: `none`,
`ongoing`, `momentum` or `ended`.

`key` `type` is `down` or `up`. `keyCode` is the macOS virtual key code, and `characters` and
`charactersIgnoringModifiers` are `NSEvent`'s. A key held with Control and without Command
carries `commands`: the selectors the system's key bindings give it, such as
`moveToBeginningOfParagraph:` or `deleteToEndOfParagraph:`. The engine interprets every other key.
