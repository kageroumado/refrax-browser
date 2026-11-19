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
| `start` | `storagePath`, `languages`, `supportDirectory` | The contract's `EngineConfiguration`, with the storage directory as a path, and the engine bundle's `Contents/Resources`, where a host finds what the bundle carries for it (`procedural.js`, the script that applies content blocking's procedural filters to a page). Answered by `started` or `startFailed` |
| `makePage` | `page`, `spec` (the contract's `EnginePageSpec`), `width`, `height`, `scale`, `framesPerSecond` | A new page of that size in points |
| `closePage` | `page` | Nothing more is sent about the page, either way |
| `command` | `page`, `command` (a `PageCommand`) | |
| `evaluate` | `page`, `id`, `request` (a `ScriptRequest`) | Answered by `evaluated` |
| `snapshot` | `page`, `id` | Answered by `snapshotTaken` |
| `requestLog` | `page`, `id`, `since` | The page's content-blocking decisions numbered after `since`. Answered by `requestLogged` |
| `answer` | `page`, `id`, `answer` (a `PageRequestAnswer`) | The answer to `request` `id` |
| `geometry` | `page`, `width`, `height`, `scale`, `token?` | The view's size in points and its backing scale. With `token`, the window's frame waits for the page's frame of that size (§10) |
| `resizeBegin` | `page`, `token` | A resize starts whose frame the window waits for (§10) |
| `resizeCommit` | `page`, `token` | The window's frame is committed: the host lets the page's held frame show. Answered by `resizeCommitted` |
| `focusState` | `page`, `focused` | Whether the view is the first responder of the key window |
| `mouse` | `page`, `type`, `x`, `y`, `screenX`, `screenY`, `button`, `buttons`, `modifiers`, and `clickCount` or the wheel fields | §5 |
| `key` | `page`, `id`, `type`, `keyCode`, `characters`, `charactersIgnoringModifiers`, `modifiers`, `repeat`, `commands` | §5. Answered by `keyHandled` or `keyUnhandled` |
| `edit` | `page`, `action`: `selectAll` \| `copy` \| `cut` \| `paste` \| `undo` \| `redo` | A command from Refrax's Edit menu |
| `composition` | `page`, `text` | The text an input method is composing at the caret; empty when it composes none (§7) |
| `insertText` | `page`, `text`, `replacementStart`, `replacementLength` | Text for the focused field from an input method or the system (§7) |
| `contextMenuChoice` | `page`, `id`, `item?` | The item chosen from `contextMenu` `id`, or none (§8) |
| `policy` | `update` (a `PolicyUpdate`) | |
| `accessibility` | `page`, `enabled` | Something read the view's accessibility children: the host builds the page's tree and keeps the client told of it (§6) |
| `accessibilityAction` | `page`, `node`, `action`: `press` \| `focus` | An assistive technology acted on a node |
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
| `requestLogged` | `page`, `id`, `log` | The contract's request log answer: `{ "entries", "nextSequence" }` |
| `layer` | `page`, `contextID` | The Core Animation context the page renders into, shown with a `CALayerHost`; 0 for none |
| `accessibilityTree` | `page`, `root`, `nodes` | The page's whole accessibility tree (§6) |
| `accessibilityChanges` | `page`, `nodes`, `removed` | The nodes that are new or changed, and the numbers of the ones that are gone (§6) |
| `inputMethod` | `page`, `enabled`, `caret?`, `cursor`, `anchor`, `textBefore`, `textAfter` | The page's text input, each time it changes (§7) |
| `contextMenu` | `page`, `id`, `x`, `y`, `items` | A menu to show at a point of the view. Answered by `contextMenuChoice` (§8) |
| `dragStarted` | `page`, `items`, `title` | The user began dragging something of the page's (§9) |
| `resizeHeld` | `page`, `token` | The page's frame of the size `geometry` named is ready and held (§10) |
| `resizeCommitted` | `page`, `token` | The held frame is showing |
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

## 6. Accessibility

The client makes the page's accessibility tree out of elements in Refrax's process, under the
page's view, from what the host sends: nothing is built until something reads the view's
accessibility children, which sends `accessibility`. Each `accessibilityTree` replaces the tree
before it. `accessibilityChanges` changes the tree held: each node of `nodes` replaces the one
with its number or joins the tree, taking the children it names from the parents they had, and
the nodes numbered in `removed` leave it. A node of `nodes`:

| Field | Meaning |
|---|---|
| `id` | The node's number, the same for as long as the node lives |
| `role`, `subrole?`, `roleDescription?` | AppKit's names (`AXWebArea`, `AXButton`, `AXStaticText`, …) |
| `label?`, `title?`, `value?`, `help?`, `url?` | What the element says of itself; `value` is text or a number |
| `frame` | `[x, y, width, height]` in points from the top left of the view |
| `children` | The numbers of the nodes under it, in order |
| `focused?`, `disabled?` | |

## 7. Text input

The view is the page's `NSTextInputClient` while `inputMethod` says `enabled`: the focused
element takes text. `caret` is the caret's rectangle, `[x, y, width, height]` in points from the
top left of the view, where an input method puts its candidates. `cursor` and `anchor` are the
ends of the selection in the focused text, in UTF-16 code units, and `textBefore` and
`textAfter` the text on either side of `cursor`, up to as much as the engine gives.

A key goes through the input method first. One it uses never becomes a `key`: the page hears
`composition` with the text being composed, each time it changes, and `insertText` with the
text to put in its place. `replacementStart` and `replacementLength` name text to replace as
well, counted from `cursor` in UTF-16 code units (0 and 0 for none): a press-and-hold accent
replaces the letter before the caret. A key that types its own character, with no composition
under way, is a `key` as ever.

## 8. Context menus

The host decides what a menu offers and the client shows it as an `NSMenu`, at `x` and `y` in
points from the top left of the view. An item of `items` is `{ "separator": true }` or
`{ "item", "title", "enabled?" }`, where `item` is the number `contextMenuChoice` names it by.
The client answers every `contextMenu` once, with the item the user chose or with none when the
menu closed without one. The host does what the item means: a link to open goes to Refrax as
the contract's `openURL`.

The menu takes the mouse, so before it opens the client sends `mouse` `up` for each button the
page had down.

## 9. Dragging out of the page

The engine runs a drag of the page's content from the `mouse` messages it gets. `dragStarted`
makes that drag the system's as well, so it can end on Refrax's own windows or another
application: `items` are the text of the page's drag data, each `{ "type", "value" }` with a
MIME type (`text/uri-list`, `text/plain`, `text/html`), and `title` names what is dragged. The
client offers the first `http` or `https` URL of a `text/uri-list` as a link.

While the system's drag runs, the client sends `mouse` `move` for the pointer wherever it is,
and `mouse` `up` for the primary button where the drag ends, so the engine's own drag and drop
goes on over the page and ends with the system's.

## 10. Resizing

A view that changes size shows the page's last frame stretched or cut short until the page has
laid out again. To change both in one frame, the client sends `resizeBegin` when the view's
size changes, then, as its window's frame is about to be committed, `geometry` with the same
`token`, and waits up to one frame of the display for `resizeHeld`: the host has the page's
frame of that size and holds it. Once the window's frame is committed the client sends
`resizeCommit`, and the host shows the held frame and answers `resizeCommitted`.

A page that misses the wait is not waited for again until the resizing pauses; its `geometry`
then carries no `token`. A host with no way to hold a frame answers `resizeHeld` and
`resizeCommitted` at once.
