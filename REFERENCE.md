# refrax-browser reference

[Overview](README.md)

## Engines

Refrax renders with **WebKit** out of the box and can add **Chromium**:

1. **Install it** in **Settings → Engines**. Refrax downloads the engine and keeps it updated alongside the app.
2. **Pick the default engine** in the same pane: new pages render with it.
3. **Reload any tab in another engine** from the reload button's menu, or **View → Reload in Chromium** (or WebKit). A tab remembers its engine.

Your tabs, spaces, history, content blocking, per-site settings, routing rules and
pinned-tab previews work with either engine, and `refrax-ctl` drives both the same way.

Refrax talks to an engine only through a documented contract,
[`Engines/CONTRACT.md`](Engines/CONTRACT.md): events out, commands in, and requests Refrax
answers, over the binary interface in [`Engines/SDK/RFXEngine.h`](Engines/SDK/RFXEngine.h).
Chromium is one implementation (its host lives in [`Engines/Chromium`](Engines/Chromium)); any
engine that implements the contract can plug in, and
[`Engines/Conformance`](Engines/Conformance) checks an engine bundle against it. Refrax currently
loads only engines signed by the Refrax team: the contract describes trusting another
developer's signature, and Refrax doesn't implement that step yet.

## Architecture

- **Tab** contains one or more **TabPages** (SwiftData, persisted)
- **WebPage**: runtime-only page, created on demand by **WebPagePool**, rendered by WebKit or by a plug-in engine behind the engine contract
- **WebView**: SwiftUI view displaying a WebPage (1:1)
- **Pattern**: environment injection with a Manager (Store) pattern — views consume managers via `@Environment`
