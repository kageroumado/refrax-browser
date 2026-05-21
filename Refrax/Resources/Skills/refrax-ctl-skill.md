---
name: refrax-ctl
description: Browse the web, fetch pages, and automate browser interactions via Refrax. Use this skill whenever the user's task involves fetching web content, reading web pages, researching topics online, opening URLs, taking screenshots of websites, filling out web forms, managing browser tabs, or any web-related task — even if they don't mention "browser" or "Refrax" explicitly. If a task requires accessing a URL or interacting with a web page, this skill applies. Refrax auto-launches if not running. Do NOT use for general macOS automation unrelated to the web.
license: MIT
compatibility: Requires macOS with Refrax browser installed. Auto-launches if not running. Works in Claude Code, Claude.ai with code execution, and custom agents.
metadata:
  author: kageroumado
  version: 2.0.0
---

Refrax is a WebKit browser controlled via the `refrax-ctl` CLI. It auto-launches if not running — just run any command.

## Choosing the Right Command

Pick based on what you need:

| Intent | Command | Creates tab? |
|--------|---------|-------------|
| **Read a web page** (most common) | `refrax-ctl fetch URL` | No — headless, uses browser cookies |
| **Show the user a page** | `refrax-ctl navigate URL` | Yes — opens a new tab |
| **Navigate an existing tab** | `refrax-ctl tab navigate URL` | No — reuses current tab |
| **Read the current tab** | `refrax-ctl read` | No |

`fetch` is your default for reading web content. It loads pages headlessly (no tab, no UI) with the browser's cookies and content blockers — think of it as `curl` with a full browser engine.

## Content Scopes

All read commands accept `--scope` to control what you get back:

| Scope | What it returns | Best for |
|-------|----------------|----------|
| `viewport` (default) | Structured content in a 1024x768 viewport — element refs, ARIA roles, links | Interacting with elements, clicking, form filling |
| `full` | Structured content for the entire page | Reading long articles, full page analysis |
| `main` | Structured content for the main content area | Articles, blog posts (skips nav/footer) |
| `text` | Plain text (`document.body.innerText`) | Summarization, text analysis, minimal tokens |
| `html` | Raw HTML source | Parsing, scraping, debugging |

**For reading/research tasks, use `--scope text` or `--scope main`** — they return focused content without element refs, keeping your context lean.

## Quick Reference

```bash
refrax-ctl fetch URL [--scope S] [--timeout N]         # Headless page read
refrax-ctl navigate URL [--read] [--wait] [--activate]  # Open in new tab
refrax-ctl tab navigate URL [--tab ID] [--read]         # Navigate existing tab
refrax-ctl read [--tab ID] [--scope S]                  # Read current tab
refrax-ctl open URL [--activate]                        # Open new tab (no read)
refrax-ctl screenshot [window|visible|full] [--output PATH]
refrax-ctl state [--json]                               # Full browser state
refrax-ctl ping                                         # Check if running
```

## Interacting with Pages

Page content in `viewport` or `full` scope includes element refs (like `e1`, `e5`) that you can use to click, type, and interact:

```bash
refrax-ctl read                            # Get page content with element refs
refrax-ctl click e5                        # Click element by ref
refrax-ctl click "Sign In" --fuzzy         # Click by visible text
refrax-ctl click e5 --read                 # Click + get updated content
refrax-ctl type "search query"             # Type into focused element
refrax-ctl type "text" --element e3        # Type into specific element
refrax-ctl scroll down --amount 500        # Scroll down
```

**Workflow**: Read the page (viewport scope) → find the element ref → interact → read again to verify.

## Multi-Step Automation

For complex workflows, use `exec` programs. Only `emit`/`emit_json` output enters your context — intermediate steps stay internal.

```bash
refrax-ctl exec 'navigate "https://example.com" --wait
$content = read_page viewport
$link = find $content where tag=a text contains "login"
emit "Login link: ${link.href}"'
```

For full DSL syntax (variables, control flow, element queries, form filling, `request_human`), load `references/dsl.md`.

## When to Ask the Human for Help

Do NOT try to handle these yourself — ask the user or use `request_human` in exec programs:

- CAPTCHAs or bot detection
- Login prompts (never enter credentials without explicit instruction)
- Two-factor authentication
- Purchases or account changes
- Anything requiring visual judgment you can't verify

## References

| Reference | Load when |
|---|---|
| `references/dsl.md` | Writing `exec` programs — DSL syntax, variables, control flow, all commands |
| `references/commands.md` | Full CLI command reference — tab management, spaces, groups, bookmarks, history, dev tools, window control, visual feedback |
| `references/security.md` | Security policies, rate limits, authentication, sensitive field detection |

## Tab References

Commands accepting `--tab` support flexible references:

| Format | Example |
|--------|---------|
| Index | `3` (1-based in current space) |
| Keyword | `active`, `first`, `last`, `next`, `prev` |
| Title | `title:GitHub` |
| URL | `url:github.com` |
| Fuzzy | `"Hacker News"` |

## Troubleshooting

- **Connection refused** — Refrax should auto-launch; if not, run `open -a Refrax` manually
- **"Request timed out"** — Use `--timeout N` for slow pages, or check with `refrax-ctl state`
- **"Tab has N pages"** — Split-view tab; the error lists page IDs, use `--page PAGE_ID`
