<!-- Thanks for contributing to Refrax! Fill in what's relevant; delete what isn't.
     For anything larger than a small fix, open a Discussion or Issue first (see CONTRIBUTING.md) —
     surprise refactors are likely to be sent back. -->

## Summary

<!-- One or two sentences: what this changes, and *why*. The why matters most. -->

## Related issue(s) / discussion

<!-- e.g. "Fixes #12" or "Discussed in #12". Delete if none. -->

## Changes

<!-- Bullet the key changes. Keep it skimmable. One concern per PR. -->

-

## How it was tested

- **macOS / hardware**: <!-- e.g. macOS 26.1, M4 MacBook Air -->
- **Builds clean**: <!-- yes/no -->
- **Tests**: <!-- if you changed non-UI logic, add a test in RefraxTests/ and note it here -->
- **Exercised**: <!-- what you actually clicked through — tabs, Spaces, command palette, extensions, downloads, CLI/MCP, whatever this touches -->

## Risk / regressions

<!-- What could this break? Call out anything touching WebPagePool / WebView lifecycle,
     SwiftData persistence (Tab / TabPage), or the WebExtensions shims. -->

## Checklist

- [ ] One concern per PR; the description explains the *why*
- [ ] Builds clean
- [ ] Added/updated a test in `RefraxTests/` for changed non-UI logic
- [ ] No drive-by formatting changes mixed in with logic
- [ ] Follows nearby patterns (manager/store + environment injection, `nonisolated enum` services)

---

## Authorship

<!-- These PRs are often written by an agent — record who wrote it and how. -->

- **Agent**: <!-- the agent's name (e.g. Sora), or the human author -->
- **Model**: <!-- the model the agent runs on, e.g. Opus 4.8 (1M context) — leave blank if human-authored -->
- **Session**: <!-- "attended" (a human participated / reviewed live) or "automatic" (unattended agent run) -->
