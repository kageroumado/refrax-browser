# Security

Refrax is a browser. If you've found a security issue, please don't
open a public issue.

**Report privately** via [GitHub Security Advisories](../../security/advisories/new),
or by email to <security@refrax.website>.

Include enough detail to reproduce: what you did, what happened, the
Refrax and macOS versions, and a proof-of-concept if you have one.

I'm a solo maintainer. I'll get to it when I can, and I'll keep you in
the loop while I do.

## In scope

- Bypasses of Refrax's own privacy features (tracker stripping, AMP
  rewriting, content blockers, GPC, link sanitizer)
- Leaks from the password manager, AutoFill, or keychain integration
- Cross-space / cross-window data leakage that breaks isolation
- Agent prompt-injection that lets a page act outside its permissions
- Issues in `refrax-ctl` or the control server (Unix socket, auth)
- Sync-data exposure
- Anything in the mTLS / client-certificate UI

## Out of scope

- WebKit itself — report those to Apple
  (<https://developer.apple.com/security-bounty/>)
- Bugs only reproducible in modified forks
- Social engineering / phishing
- Issues needing physical access to an unlocked device

If a WebKit issue is *exposed by something Refrax does on top of WebKit*,
that's in scope. Tell me.

## Disclosure

Default is 90 days from when you tell me, or sooner if a fix ships.
We can agree on something different if the situation calls for it.

I'll credit you in the advisory unless you'd rather stay anonymous.
There's no bounty program — just gratitude.
