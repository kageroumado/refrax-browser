# Refrax's patches to Chromium

Applied by `forge prepare` after ungoogled-chromium's, in file-name order, each with
`patch -p1`. Every edit to an upstream file is listed here with the reason it can't live in
`//refrax`. Diffs are taken against the tree *after* ungoogled's patches.

## `base-mac-attach-pump.patch`

The client runs inside Refrax, whose `-[NSApplication run]` already owns the main thread. base
lets a main-thread message pump attach to a running loop only on iOS
(`MessagePumpUIApplication::Attach`). This widens the attach path (`MessagePumpCFRunLoopBase`
`Attach`/`OnAttach`, `ThreadController::AttachToMessagePump`, `CurrentUIThread::Attach`) to
all Apple platforms and gives `MessagePumpNSApplication` an `Attach`/`Detach` that mirror iOS's.
Chrome itself never calls them; its behavior is unchanged.

## `chrome-refrax-host.patch`

- `chrome/app/chrome_main_delegate.cc`: constructs `refrax::HostContentBrowserClient`, Chrome's
  browser client plus the engine host's startup parts. Inert unless the process was launched
  with `--refrax-bootstrap`.
- `chrome/BUILD.gn`: links `//refrax/host` into `chrome_dll`. Editing
  `chrome_browser_main.cc` instead would make `//chrome/browser` depend on `//refrax/host`,
  which depends on `//chrome/browser`.
- `chrome/browser/ui/tab_helpers.h`: befriends `refrax::HostPage` so a page gets the full set of
  tab helpers (session ids, zoom, permissions, popup blocking, dialogs, extensions) without a
  `Browser`.

## `os-crypt-keychain-name.patch`

`components/os_crypt/common/keychain_password_mac.mm`: the engine's cookie and password
encryption key lives in its own keychain item, "Refrax Chromium Safe Storage". Every
non-Google Chromium shares "Chromium Safe Storage", whose access list belongs to whichever
Chromium created it; the host would block on a keychain prompt it has no UI to show, which
stalls every HTTP load and the host's shutdown.
