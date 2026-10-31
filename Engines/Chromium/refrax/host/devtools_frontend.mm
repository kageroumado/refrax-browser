// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/devtools_frontend.h"

#import <AppKit/AppKit.h>

#include <utility>

#include "base/functional/bind.h"
#include "base/task/sequenced_task_runner.h"
#include "base/values.h"
#include "chrome/browser/devtools/devtools_ui_bindings.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/webui/devtools/devtools_ui.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"
#include "ui/gfx/geometry/rect.h"

namespace refrax {

namespace {

constexpr char kFrontendURL[] = "devtools://devtools/bundled/devtools_app.html";

}  // namespace

// What the DevTools frontend asks of the window it lives in. Owned by the frontend's
// DevToolsUIBindings, which is deleted with the frontend's WebContents.
class DevToolsFrontend::BindingsDelegate : public DevToolsUIBindings::Delegate {
 public:
  BindingsDelegate(base::WeakPtr<DevToolsFrontend> frontend, content::WebContents* inspected)
      : frontend_(std::move(frontend)), inspected_(inspected) {}

  content::WebContents* GetInspectedWebContents() override { return inspected_; }
  void ActivateWindow() override {}
  void CloseWindow() override {
    if (frontend_) {
      frontend_->RequestClose();
    }
  }
  void Inspect(scoped_refptr<content::DevToolsAgentHost> host) override {}
  void SetInspectedPageBounds(const gfx::Rect& rect) override {}
  void InspectElementCompleted() override {}
  void SetIsDocked(bool is_docked) override {}
  void OpenInNewTab(const std::string& url) override {
    if (frontend_) {
      frontend_->OpenURL(url);
    }
  }
  void OpenSearchResultsInNewTab(const std::string& query) override {}
  void SetWhitelistedShortcuts(const std::string& message) override {}
  void SetEyeDropperActive(bool active) override {}
  void OpenNodeFrontend() override {}
  void InspectedContentsClosing() override {
    if (frontend_) {
      frontend_->RequestClose();
    }
  }
  void OnLoadCompleted() override {
    if (frontend_) {
      frontend_->OnLoaded();
    }
  }
  void ReadyForTest() override {}
  void ConnectionReady() override {}
  void SetOpenNewWindowForPopups(bool value) override {}
  infobars::ContentInfoBarManager* GetInfoBarManager() override { return nullptr; }
  void RenderProcessGone(bool crashed) override {
    // A frontend without its renderer is a blank window: closed, to be opened afresh.
    if (frontend_) {
      frontend_->RequestClose();
    }
  }
  void ShowCertificateViewer(const std::string& cert_chain) override {}
  int GetDockStateForLogging() override { return 0; }
  int GetOpenedByForLogging() override { return 0; }
  int GetClosedByForLogging() override { return 0; }

 private:
  base::WeakPtr<DevToolsFrontend> frontend_;
  raw_ptr<content::WebContents> inspected_;
};

DevToolsFrontend::DevToolsFrontend(content::WebContents* inspected,
                                   remote_cocoa::mojom::Application* application,
                                   uint64_t container_ns_view_id,
                                   Panel panel,
                                   base::OnceClosure on_closed,
                                   base::RepeatingCallback<void(const GURL&)> open_url,
                                   base::RepeatingCallback<bool(const input::NativeWebKeyboardEvent&)>
                                       unhandled_key)
    : inspected_(inspected),
      application_(application),
      container_ns_view_id_(container_ns_view_id),
      pending_panel_(panel),
      on_closed_(std::move(on_closed)),
      open_url_(std::move(open_url)),
      unhandled_key_(std::move(unhandled_key)) {
  Profile* profile = Profile::FromBrowserContext(inspected->GetBrowserContext());
  frontend_ = content::WebContents::Create(content::WebContents::CreateParams(profile));
  frontend_->SetDelegate(this);

  std::string url = std::string(kFrontendURL) +
                    "?remoteBase=" + DevToolsUI::GetRemoteBaseURL().spec() +
                    "&targetType=tab";
  if (panel == Panel::kConsole) {
    url += "&panel=console";
  } else if (panel == Panel::kElementSelection) {
    url += "&panel=elements";
  }
  // Navigating to the frontend's URL creates its DevToolsUIBindings (the devtools: WebUI).
  frontend_->GetController().LoadURL(DevToolsUIBindings::SanitizeFrontendURL(GURL(url)),
                                     content::Referrer(),
                                     ui::PAGE_TRANSITION_AUTO_TOPLEVEL, std::string());
  if (DevToolsUIBindings* bindings = DevToolsUIBindings::ForWebContents(frontend_.get())) {
    bindings->SetDelegate(new BindingsDelegate(weak_factory_.GetWeakPtr(), inspected));
    bindings->AttachTo(content::DevToolsAgentHost::GetOrCreateForTab(inspected));
  }
}

DevToolsFrontend::~DevToolsFrontend() {
  if (attached_) {
    hostable_view()->ViewsHostableDetach();
  }
  if (frontend_) {
    frontend_->SetDelegate(nullptr);
  }
}

ui::ViewsHostableView* DevToolsFrontend::hostable_view() const {
  NSView* view = frontend_->GetNativeView().GetNativeNSView();
  return [static_cast<id<ViewsHostable>>(view) viewsHostableView];
}

void DevToolsFrontend::Attach() {
  if (attached_) {
    return;
  }
  hostable_view()->ViewsHostableAttach(this);
  attached_ = true;
  SetSize(size_);
  hostable_view()->ViewsHostableSetVisible(true);
  hostable_view()->ViewsHostableMakeFirstResponder();
  frontend_->Focus();
}

void DevToolsFrontend::SetSize(const gfx::Size& size) {
  size_ = size;
  if (attached_ && !size_.IsEmpty()) {
    hostable_view()->ViewsHostableSetBounds(gfx::Rect(size_), size_.height());
  }
}

void DevToolsFrontend::Show(Panel panel) {
  pending_panel_ = panel;
  if (loaded_) {
    OnLoaded();
  }
}

void DevToolsFrontend::OnLoaded() {
  loaded_ = true;
  DevToolsUIBindings* bindings = DevToolsUIBindings::ForWebContents(frontend_.get());
  if (!bindings) {
    return;
  }
  switch (pending_panel_) {
    case Panel::kConsole:
      bindings->CallClientMethod("DevToolsAPI", "showPanel", base::Value("console"));
      break;
    case Panel::kElementSelection:
      bindings->CallClientMethod("DevToolsAPI", "enterInspectElementMode");
      break;
    case Panel::kDefault:
      break;
  }
  pending_panel_ = Panel::kDefault;
}

void DevToolsFrontend::RequestClose() {
  if (on_closed_) {
    // Posted: the frontend's bindings are mid-call, and the owner deletes this.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, std::move(on_closed_));
  }
}

bool DevToolsFrontend::HandleKeyboardEvent(content::WebContents* source,
                                           const input::NativeWebKeyboardEvent& event) {
  return unhandled_key_.Run(event);
}

void DevToolsFrontend::OpenURL(const std::string& url) {
  GURL target(url);
  if (target.SchemeIsHTTPOrHTTPS()) {
    open_url_.Run(target);
  }
}

ui::Layer* DevToolsFrontend::GetUiLayer() const {
  return nullptr;
}

remote_cocoa::mojom::Application* DevToolsFrontend::GetRemoteCocoaApplication() const {
  return application_;
}

uint64_t DevToolsFrontend::GetNSViewId() const {
  return container_ns_view_id_;
}

void DevToolsFrontend::OnHostableViewDestroying() {
  attached_ = false;
}

}  // namespace refrax
