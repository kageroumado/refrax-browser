# refrax-ctl — Security & Rate Limits

Load this reference when working with security policies, understanding execution limits, or debugging authentication issues.

## Security Policy

Programs executed via `refrax-ctl exec` run under a security policy with two-phase enforcement. A program runs under the default limits unless `exec --permissive` asks for the permissive ones.

### Limits

| Limit | Default | Permissive (`--permissive`) |
|-------|---------|----------------------|
| Max navigations | 10 | 100 |
| Max interactions (click/type/fill/hover/select) | 50 | 500 |
| Max page reads (read_page/screenshot) | 20 | 200 |
| Max loop iterations | 100 | 100 |
| JavaScript (`page_exec`) | blocked | allowed |
| Max execution time | 60s | 300s |
| Sensitive fields | require confirmation | allow |

Domain allow and block lists match a domain and its subdomains: `example.com` covers `www.example.com`, never `notexample.com`.

### Phase 1: Static Analysis (Pre-Execution)

Before any code runs, the program is analyzed and rejected immediately if any static limit is exceeded:

- Counts `navigate` commands against max navigations
- Counts interaction commands against max interactions
- Counts `read_page`/`screenshot` against max page reads
- Checks for `page_exec` when JavaScript is blocked
- Validates static navigate URLs against domain allow/block lists

Variable-based URLs can't be checked statically and are deferred to runtime.

### Phase 2: Runtime Enforcement

During execution:

- **Counters** increment per-operation; throw immediately on limit breach
- **Domain checks** after each navigation completes (catches redirects to blocked domains)
- **Timeout** checked before each line; exceeding deadline aborts
- **Loop iterations** bounded per `for` loop

### What to do when you hit limits

- Break your task into smaller programs
- Use individual commands instead of a program
- For longer tasks, use `--timeout` with `exec`; it is capped at the policy's execution time (60 seconds, or 300 with `--permissive`)

## Sensitive Field Detection

When `fill` targets a form field, the system checks if the field is sensitive:

**Detected as sensitive:**
- `inputType == "password"`
- Field name/ref matching: `password`, `passwd`, `secret`, `credit.?card`, `cc.?num`, `card.?number`, `cvv`, `cvc`, `csc`, `ssn`, `social.?security`, `routing.?number`, `account.?number`

**Default behavior:** The fill command will throw with `[CONFIRM_REQUIRED]`. The user sees a confirmation dialog. Use `request_human` instead of trying to bypass this.

## Navigation

Commands that open a URL (`navigate`, `open`, `tab navigate`, `fetch`, and the `navigate` step of a program) accept `http`, `https`, and `about` URLs. An address with no scheme opens as `https`. Every other scheme, `file` included, is refused with `scheme_not_allowed`.

## Locked Spaces

A locked space is invisible to `refrax-ctl` until the user unlocks it in Refrax: its tabs are left out of `state`, `tab list`, and every tab reference, and naming one of its tabs, pages, or the space itself for an action fails with `space_locked`. A locked space cannot be deleted, updated, or receive tabs over the control socket.

## Cookies

`dev cookies` and `cookies export` read a space's cookie store directly, under the space's "Allow command-line tools to read this space's cookies" setting. That setting governs only these two commands. Every other command acts inside the page, with the signed-in session the page already has: `exec`, `page`, `click`, `fetch --space` and the rest send the site's cookies as a browser tab would.

`dev cookies --domain` takes a registrable domain such as `example.com`; a single label or a public suffix such as `com` or `co.uk` is refused.

`cookies export` writes values to the login keychain with an access list that trusts `refrax-ctl` and `/usr/bin/security`. Since `/usr/bin/security` reads the item without a prompt, any process you run can read an exported cookie.

## Authentication

The control server authorizes the app a client acts for, identified by its code signature.

### Access Modes

| Mode | Behavior |
|------|----------|
| Off | Socket not running; no CLI access |
| Ask for Permission | Refrax asks once per app; apps the user always allows are remembered by their code signature |
| Allow All Signed Apps | Any app running as the same user whose code has a valid signature from Apple or an identified developer is accepted; unsigned and ad hoc signed code is refused |

Configured in Refrax Settings > Advanced. Default is "Ask for Permission". The mode and the list of allowed apps live in Refrax's keychain items on this Mac; they never sync.

### Who gets asked about

- When `refrax-ctl` connects, Refrax asks about the app that ran it: the app macOS holds responsible for the process (Terminal, an editor, an agent's app), else the nearest app among its parent processes. The prompt reads "Allow <App> to control Refrax via refrax-ctl?".
- With no app in the chain (a launchd job, cron, a shell over SSH), the prompt names the process that ran `refrax-ctl` and says it is a background process.
- Any other program connecting to the socket is asked about itself.
- Deny is the default button. "Allow Once" lasts until that app or Refrax quits. "Always Allow" remembers the app's code requirement (team and bundle identifier, or Apple and identifier), never a path; it is offered only for validly signed code.
- After a Deny, the same app is refused without a prompt for 60 seconds. Connections that arrive while a prompt is open wait for its answer.

### Connection Security

- Socket uses `0600` permissions (owner-only)
- Peer UID is verified — different-user connections are rejected unconditionally
- The peer is identified by the socket's audit token and its signature is validated. `refrax-ctl` counts as Refrax's own only when it is signed by the developer team that signed the running Refrax; any other copy of `refrax-ctl` is refused with `untrusted_client`
- `refrax-ctl` checks the same way that the socket belongs to the Refrax app signed by its own team before sending a request, and exits with `untrusted server` otherwise
- Neither side names a team: each reads its own signing team at runtime, so a build signed by another developer pairs with that developer's other half. An ad hoc signed or unsigned build has no team, and refuses rather than trusts: Refrax refuses `refrax-ctl`, and `refrax-ctl` refuses to send
- At most 8 clients are served at once

### If connection is refused

1. Check that Refrax is running: `refrax-ctl ping`
2. Check that CLI control is not set to "Off" in Settings > Advanced
3. If in "Ask for Permission" mode, the user may need to approve the connection in the Refrax dialog; after a Deny, wait a minute before retrying
4. `untrusted_client` or `untrusted server`: `refrax-ctl` and Refrax were signed by different teams, or one of them by none. Use the `refrax-ctl` that ships with the running Refrax
