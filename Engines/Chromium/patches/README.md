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

## `chrome-renderer-refrax-agents.patch`

`chrome/renderer/chrome_content_renderer_client.cc` and `chrome/renderer/BUILD.gn`: attach two
per-frame agents the engine host drives, both inert without it:

- `js_injection::JsCommunication` (WebView's script-injection renderer half), with its
  document-start and document-end scripts run before extensions' (which may destroy the
  frame). The host installs the contract's `scripts` policy and message channels through it
  (`//refrax/host/page_scripts.cc`).
- `refrax::FrameScripts` (`//refrax/renderer`), which runs `evaluateScript` in any of
  Refrax's worlds, awaiting promises and activating the frame only when asked. Content's
  browser-side script APIs reach only content's own world ids (`ISOLATED_WORLD_ID_MAX`) and
  never await promises.

## `permissions-view-factory.patch`

`components/permissions/permission_request_manager.h`: a public `set_view_factory`, beside the
existing `set_view_factory_for_testing`, so the engine host can give each page a prompt that
sends permission questions to Refrax (`//refrax/host/permission_prompt.cc`) instead of Chrome's
bubbles, which need a Browser window.

## `download-delegate-factory.patch`

`chrome/browser/download/download_core_service{.h,.cc,_impl.cc}`: an embedder factory for the
download delegate each profile creates, so Refrax's `DownloadDelegate` (which asks Refrax
where each download goes) goes through the profile's full download setup.
`SetDownloadManagerDelegateForTesting` replaces the delegate after that setup has been skipped,
including the history service's next download id, and no download ever starts.
