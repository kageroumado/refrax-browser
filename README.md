# Refrax

refrax is a maximalist browser. while everyone else was removing
features and calling it design, i kept adding them — natively,
properly, in Swift and WebKit, the way Apple would if Apple still
shipped weird software. vertical tabs, spaces with Touch ID locks, a
command palette that takes plain language, a CLI that scripts the
entire browser, an MCP server so your agent browses beside you. it has
more features than any browser you've used and several that exist
nowhere else. seventeen people use it every week. i'm one of them.

<p align="center">
  <img src=".github/screenshot.avif" alt="Refrax browser: sidebar with grouped tabs and spaces, Liquid Glass interface, with a webpage in the main pane" width="800">
</p>

The website is at <https://refrax.browser>. Builds and updates are
distributed from there.

## License

Refrax is free software, licensed under the **GNU General Public
License, version 3** — see [LICENSE](LICENSE).

The **Refrax name and icon are trademarks** of kageroumado and are not
covered by the GPL. If you fork and redistribute, you must rebrand —
see [TRADEMARK.md](TRADEMARK.md) for the policy.

In short: study, modify, and contribute freely. Just don't ship a
modified version *as Refrax*.

## Architecture

- **Tab** contains one or more **TabPages** (SwiftData, persisted)
- **WebPage**: Runtime-only WKWebView wrapper, created on-demand by
  **WebPagePool**
- **WebView**: SwiftUI view displaying a WebPage (1:1)
- **Pattern**: Environment injection with a Manager (Store) pattern —
  views consume managers via `@Environment`

## Project layout

```
Refrax/                     The app source
RefraxTests/                Swift Testing suites
RefraxWidgets/              Widget extension
refrax-ctl/                 Headless CLI for controlling the browser
Packages/refrax-protocol/   Swift package shared by app + CLI
Scripts/                    Build-time scripts (palette generator)
Refrax.xcodeproj/           Xcode project
```

## Building

Requirements:

- macOS 26 or later
- Xcode 26 or later
- Swift 6.2

First-time setup installs Homebrew, SwiftFormat, SwiftLint, and a
pre-commit hook:

```bash
./setup.sh
```

Then open `Refrax.xcodeproj` in Xcode and build the `Refrax` scheme.

> **Note:** Code signing is intentionally not configured in this
> repository. To build locally, set your own `DEVELOPMENT_TEAM` and
> bundle identifiers in Xcode's signing settings, and provide your own
> iCloud container if you want CloudKit sync to work.

## Code style

- Swift 6.2 with strict concurrency, `@MainActor` isolation by default
- SwiftFormat runs as a pre-commit hook
- The Xcode project uses **folder references** — add and remove files
  on disk, not through the Xcode UI
- Use `Color.appAccentColor`, not `Color.accentColor`
- Extensions of built-in types live in
  `Extensions/TypeName+Extensions.swift`; extensions of project types
  go in the source file directly

## Contributing

Issues and PRs welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before
a big change.

Security issue? Don't open a public issue — see [SECURITY.md](SECURITY.md).

Also: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Contact

<requests@refrax.website>
