# refrax-ctl — Security & Rate Limits

Load this reference when working with security policies, understanding execution limits, or debugging authentication issues.

## Security Policy

Programs executed via `refrax-ctl exec` run under a security policy with two-phase enforcement.

### Default Limits (Agent Programs)

| Limit | Default | Permissive (trusted) |
|-------|---------|----------------------|
| Max navigations | 10 | 100 |
| Max interactions (click/type/fill/hover/select) | 50 | 500 |
| Max page reads (read_page/screenshot) | 20 | 200 |
| Max loop iterations | 100 | 100 |
| JavaScript (`page_exec`) | blocked | allowed |
| Max execution time | 60s | 300s |
| Sensitive fields | require confirmation | allow |

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
- For longer tasks, use `--timeout` flag with `exec`

## Sensitive Field Detection

When `fill` targets a form field, the system checks if the field is sensitive:

**Detected as sensitive:**
- `inputType == "password"`
- Field name/ref matching: `password`, `passwd`, `secret`, `credit.?card`, `cc.?num`, `card.?number`, `cvv`, `cvc`, `csc`, `ssn`, `social.?security`, `routing.?number`, `account.?number`

**Default behavior:** The fill command will throw with `[CONFIRM_REQUIRED]`. The user sees a confirmation dialog. Use `request_human` instead of trying to bypass this.

## Authentication

The control server authenticates connecting processes based on the configured access mode.

### Access Modes

| Mode | Behavior |
|------|----------|
| Off | Socket not running; no CLI access |
| Ask for Permission | Unknown binaries trigger an approval dialog; approved binaries pass through |
| Allow All | Any process running as the same user is accepted |

Configured in Refrax Settings > Advanced. Default is "Ask for Permission".

### Connection Security

- Socket uses `0600` permissions (owner-only)
- Peer UID is verified — different-user connections are rejected unconditionally
- Client identity is resolved via executable path and code signing
- In "Ask for Permission" mode, unknown clients trigger an approval dialog with "Always Allow" / "Allow Once" / "Deny" options

### If connection is refused

1. Check that Refrax is running: `refrax-ctl ping`
2. Check that CLI control is not set to "Off" in Settings > Advanced
3. If in "Ask for Permission" mode, the user may need to approve the connection in the Refrax dialog
