# Refrax

Refrax lets each tab use WebKit or Chromium while keeping the same spaces, history and site settings. Its `refrax-ctl` CLI gives scripts and agents control of both engines; spaces can be locked with Touch ID.

[Download](https://kagerou.glass/get/refrax?from=readme)

![Refrax](.github/screenshot.avif)

## Browse and automate

- Organize vertical tabs into spaces and groups.
- Use the command palette for plain-language commands.
- Install Chromium in **Settings → Engines**, then choose a default or reload individual tabs in another engine.
- Drive tabs, spaces, navigation and screenshots with `refrax-ctl`.

The app updates itself. [Engine contract and architecture](REFERENCE.md) describe how alternate renderers connect.

## Requirements

- **macOS 26+**
- **Xcode 26+** to build, with Swift 6.2 strict concurrency enabled

## Building

First-time setup installs Homebrew, SwiftFormat, SwiftLint, and a pre-commit hook:

```bash
./setup.sh
```

Then open `Refrax.xcodeproj` in Xcode and build the `Refrax` scheme.

> **Note:** Code signing is intentionally not configured in this repository. To build
> locally, set your own `DEVELOPMENT_TEAM` and bundle identifiers in Xcode's signing
> settings, and provide your own iCloud container if you want CloudKit sync to work.

## Contribute

[Contributing](CONTRIBUTING.md) · [Security reports](SECURITY.md) · [Code of conduct](CODE_OF_CONDUCT.md) · [Trademark policy](TRADEMARK.md)

Contact: <mail@kagerou.glass>
