// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/refrax_browser_main_extra_parts.h"

#import <AppKit/AppKit.h>

#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/process/process.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/after_startup_task_utils.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "content/public/browser/render_frame_host.h"
#include "refrax/host/download_delegate.h"
#include "refrax/host/engine_connection.h"
#include "refrax/host/engine_host_impl.h"
#include "refrax/host/notifications.h"
#include "refrax/host/switches.h"

namespace refrax {

namespace {

// How long a clean exit may take after the client disconnects.
constexpr base::TimeDelta kExitDeadline = base::Seconds(10);

// The host shows nothing of its own: no Dock icon, no menu bar. Set before the application
// finishes launching, so the icon never appears.
void HideFromDock() {
  [NSApplication.sharedApplication
      setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

}  // namespace

RefraxBrowserMainExtraParts::RefraxBrowserMainExtraParts() = default;
RefraxBrowserMainExtraParts::~RefraxBrowserMainExtraParts() = default;

void RefraxBrowserMainExtraParts::PreEarlyInitialization() {
  HideFromDock();
}

void RefraxBrowserMainExtraParts::PreProfileInit() {
  // Before any profile creates its download delegate or notification service.
  DownloadDelegate::Install();
  Notifications::Get().Install();
}

void RefraxBrowserMainExtraParts::PostBrowserStart() {
  // Refrax evaluates scripts in pages it hosts (the contract's evaluateScript), as Android
  // WebView's evaluateJavascript does; content otherwise limits this to WebUI pages.
  content::RenderFrameHost::AllowInjectingJavaScript();

  // The host has no windows; without this the process would be free to quit.
  keep_alive_ = std::make_unique<ScopedKeepAlive>(
      KeepAliveOrigin::REMOTE_DEBUGGING, KeepAliveRestartOption::DISABLED);

  const std::string bootstrap_name =
      base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII(
          switches::kRefraxBootstrap);
  connection_ = EngineConnection::Connect(bootstrap_name);
  if (!connection_) {
    LOG(ERROR) << "Could not reach the Refrax client at " << bootstrap_name;
    OnClientDisconnected();
    return;
  }
  engine_ = std::make_unique<EngineHostImpl>(
      mojo::PendingReceiver<mojom::EngineHost>(connection_->TakePipe()),
      base::BindOnce(&RefraxBrowserMainExtraParts::OnClientDisconnected,
                     base::Unretained(this)));

  // Chrome counts startup as complete once a visible page it tracks has loaded, and until then
  // holds back every best-effort task, including indexing content-blocking rules. The host's
  // pages never count, so it would wait for the 3-minute failsafe; serving Refrax is its
  // startup. Posted: Chrome's startup observer registers after this, and one that registers
  // after completion gets no reference and crashes on the first page.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce([] {
        AfterStartupTaskUtils::SetBrowserStartupIsCompleteForTesting(
            StartupIsCompleteReason::kNoVisiblePageFound);
      }));
}

void RefraxBrowserMainExtraParts::PostMainMessageLoopRun() {
  engine_.reset();
  connection_.reset();
  keep_alive_.reset();
}

void RefraxBrowserMainExtraParts::OnClientDisconnected() {
  // The client owns this process: without it there is nobody to show pages to.
  LOG(WARNING) << "Refrax client disconnected; exiting";
  keep_alive_.reset();
  chrome::AttemptExit();
  // A host that lingers keeps the profile's databases open, and the next host the client
  // launches on the same storage fails on them.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE, base::BindOnce([] {
        LOG(ERROR) << "Clean exit did not finish; terminating";
        base::Process::TerminateCurrentProcessImmediately(0);
      }),
      kExitDeadline);
}

}  // namespace refrax
