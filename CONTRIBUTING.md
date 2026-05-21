# Contributing

Thanks for being here. Refrax is a solo project — I built it because no
browser felt right anymore. If you want to help, you're very welcome.

For security issues, see [SECURITY.md](SECURITY.md), not the issue tracker.

## How to engage

- **Bug?** Open an issue with steps to reproduce, the Refrax version,
  and your macOS version.
- **Feature idea?** Start a Discussion before writing code. Some ideas
  don't fit the project; let's talk first so neither of us wastes time.
- **Small fix?** Just open a PR.
- **Big change?** Open a Discussion or Issue first. Surprise refactors
  are likely to be sent back.

## Setup

```bash
./setup.sh
open Refrax.xcodeproj
```

Requires macOS 26+, Xcode 26+, Swift 6.2. Code signing is unconfigured —
set your own `DEVELOPMENT_TEAM` and bundle IDs in Xcode.

## Style

- Swift 6.2 with strict concurrency. `@MainActor` by default.
- SwiftFormat runs as a pre-commit hook (the setup script installs it).
- The Xcode project uses folder references. Add files to disk, not via
  Xcode's UI.
- Match the patterns you see in nearby code: manager/store with
  environment injection, stateless services as `nonisolated enum`,
  required dependencies as `unowned` rather than optional.

## PR expectations

- One concern per PR. Title and description should explain the *why*.
- Build clean.
- If you change non-UI logic, add a test in `RefraxTests/`.
- No drive-by formatting changes mixed in with logic changes.

## License

By contributing you agree your work is licensed under GPL-3.0, the same
as the rest of the project. The "Refrax" name and icon stay reserved —
see [TRADEMARK.md](TRADEMARK.md).

I'll try to respond reasonably quickly, but no promises. Solo project.
