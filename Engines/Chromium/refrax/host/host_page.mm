// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/host_page.h"

#import <AppKit/AppKit.h>

#include <utility>

#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/strings/utf_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/tab_helpers.h"
#include "components/remote_cocoa/browser/ns_view_ids.h"
#include "components/zoom/zoom_controller.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/result_codes.h"
#include "net/base/net_errors.h"
#include "refrax/host/contract_json.h"
#include "refrax/host/engine_host_impl.h"
#include "refrax/host/page_scripts.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "third_party/blink/public/mojom/favicon/favicon_url.mojom.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/geometry/rect.h"

namespace refrax {

namespace {

// The contract's NavigationFailure kind for a net error.
std::string_view FailureKind(int error) {
  switch (error) {
    case net::ERR_ABORTED:
      return "cancelled";
    case net::ERR_NAME_NOT_RESOLVED:
    case net::ERR_NAME_RESOLUTION_FAILED:
      return "cannotFindHost";
    case net::ERR_CONNECTION_REFUSED:
    case net::ERR_CONNECTION_FAILED:
    case net::ERR_ADDRESS_UNREACHABLE:
      return "cannotConnectToHost";
    case net::ERR_INTERNET_DISCONNECTED:
      return "notConnectedToInternet";
    case net::ERR_CONNECTION_RESET:
    case net::ERR_CONNECTION_CLOSED:
      return "connectionLost";
    case net::ERR_TIMED_OUT:
    case net::ERR_CONNECTION_TIMED_OUT:
      return "timedOut";
    case net::ERR_BLOCKED_BY_CLIENT:
    case net::ERR_BLOCKED_BY_ADMINISTRATOR:
    case net::ERR_BLOCKED_BY_RESPONSE:
      return "blockedByPolicy";
    case net::ERR_HTTP_RESPONSE_CODE_FAILURE:
      return "httpError";
  }
  return net::IsCertificateError(error) ? "certificateInvalid" : "other";
}

// The contract's openURL disposition.
std::string_view DispositionName(WindowOpenDisposition disposition) {
  switch (disposition) {
    case WindowOpenDisposition::CURRENT_TAB:
      return "currentTab";
    case WindowOpenDisposition::NEW_FOREGROUND_TAB:
    case WindowOpenDisposition::SINGLETON_TAB:
    case WindowOpenDisposition::SWITCH_TO_TAB:
      return "foregroundTab";
    case WindowOpenDisposition::NEW_BACKGROUND_TAB:
      return "backgroundTab";
    case WindowOpenDisposition::NEW_POPUP:
      return "popup";
    default:
      return "newWindow";
  }
}

// The contract's RendererTerminationReason.
std::string_view TerminationReason(base::TerminationStatus status,
                                   bool requested) {
  if (requested) {
    return "requestedByBrowser";
  }
  switch (status) {
    case base::TERMINATION_STATUS_OOM:
      return "exceededMemoryLimit";
    case base::TERMINATION_STATUS_ABNORMAL_TERMINATION:
    case base::TERMINATION_STATUS_PROCESS_CRASHED:
    case base::TERMINATION_STATUS_LAUNCH_FAILED:
      return "crashed";
    default:
      return "unknown";
  }
}

}  // namespace

HostPage::HostPage(EngineHostImpl* engine,
                   Profile* profile,
                   std::string id,
                   mojo::PendingAssociatedReceiver<mojom::Page> receiver,
                   mojo::PendingAssociatedRemote<mojom::PageClient> client)
    : engine_(engine),
      id_(std::move(id)),
      container_ns_view_id_(remote_cocoa::GetNewNSViewId()),
      web_contents_(content::WebContents::Create(
          content::WebContents::CreateParams(profile))),
      receiver_(this, std::move(receiver)),
      client_(std::move(client)) {
  // A full Chrome tab minus the tab strip: session ids, zoom, permissions, popup blocking,
  // dialogs, extensions.
  TabHelpers::AttachTabHelpers(web_contents_.get());
  web_contents_->SetDelegate(this);
  Observe(web_contents_.get());
  receiver_.set_disconnect_handler(
      base::BindOnce(&HostPage::Close, base::Unretained(this)));
  scripts_ = std::make_unique<PageScripts>(
      web_contents_.get(), &engine_->worlds(),
      base::BindRepeating(
          [](base::WeakPtr<HostPage> page, std::string message,
             base::OnceCallback<void(const std::string&)> reply) {
            if (!page) {
              return;
            }
            page->client_->OnScriptMessage(message, std::move(reply));
          },
          weak_factory_.GetWeakPtr()));
  scripts_->Apply(engine_->scripts());
}

void HostPage::ApplyScripts(const base::ListValue& scripts) {
  scripts_->Apply(scripts);
}

HostPage::~HostPage() {
  scripts_.reset();
  Observe(nullptr);
  web_contents_->SetDelegate(nullptr);
  if (attached_) {
    hostable_view()->ViewsHostableDetach();
  }
}

void HostPage::Load(const GURL& url) {
  content::NavigationController::LoadURLParams params(url);
  params.transition_type = ui::PageTransitionFromInt(
      ui::PAGE_TRANSITION_TYPED | ui::PAGE_TRANSITION_FROM_ADDRESS_BAR);
  web_contents_->GetController().LoadURLWithParams(params);
}

ui::ViewsHostableView* HostPage::hostable_view() const {
  NSView* view = web_contents_->GetNativeView().GetNativeNSView();
  return [static_cast<id<ViewsHostable>>(view) viewsHostableView];
}

void HostPage::ApplyBounds() {
  if (attached_ && !size_.IsEmpty()) {
    hostable_view()->ViewsHostableSetBounds(gfx::Rect(size_), size_.height());
  }
}

void HostPage::Emit(std::string_view name, base::DictValue fields) {
  client_->OnEvent(contract::Message(name, std::move(fields)));
}

void HostPage::EmitBackForward() {
  content::NavigationController& controller = web_contents_->GetController();
  Emit("backForwardChanged", base::DictValue()
                                 .Set("canGoBack", controller.CanGoBack())
                                 .Set("canGoForward", controller.CanGoForward()));
}

void HostPage::RequestOpenURL(const GURL& url,
                              WindowOpenDisposition disposition,
                              bool user_gesture) {
  // Refrax owns every tab and window; it opens the URL where it decides.
  client_->OnRequest(
      contract::Message("openURL",
                        base::DictValue()
                            .Set("url", contract::URLValue(url))
                            .Set("disposition", DispositionName(disposition))
                            .Set("userGesture", user_gesture)),
      base::DoNothing());
}

// MARK: mojom::Page

void HostPage::AttachView() {
  if (attached_) {
    return;
  }
  hostable_view()->ViewsHostableAttach(this);
  attached_ = true;
  ApplyBounds();
  hostable_view()->ViewsHostableSetVisible(true);
}

void HostPage::SetSize(const gfx::Size& size) {
  size_ = size;
  ApplyBounds();
}

void HostPage::PerformCommand(const std::string& command) {
  auto message = contract::ParseMessage(command);
  if (!message) {
    receiver_.ReportBadMessage("PerformCommand: malformed command");
    return;
  }
  auto& [name, fields] = *message;
  content::NavigationController& controller = web_contents_->GetController();

  if (name == "load") {
    const base::DictValue* request = fields.FindDict("request");
    const std::string* url = request ? request->FindString("url") : nullptr;
    if (!url) {
      receiver_.ReportBadMessage("load: no url");
      return;
    }
    content::NavigationController::LoadURLParams params((GURL(*url)));
    params.transition_type = ui::PageTransitionFromInt(
        ui::PAGE_TRANSITION_TYPED | ui::PAGE_TRANSITION_FROM_ADDRESS_BAR);
    if (const base::DictValue* headers = request->FindDict("headers")) {
      for (const auto [key, value] : *headers) {
        if (value.is_string()) {
          params.extra_headers += key + ": " + value.GetString() + "\r\n";
        }
      }
    }
    if (const std::string* referrer = request->FindString("referrer")) {
      params.referrer = content::Referrer(
          GURL(*referrer), network::mojom::ReferrerPolicy::kDefault);
    }
    controller.LoadURLWithParams(params);
  } else if (name == "goBack") {
    if (controller.CanGoBack()) {
      controller.GoBack();
    }
  } else if (name == "goForward") {
    if (controller.CanGoForward()) {
      controller.GoForward();
    }
  } else if (name == "reload") {
    controller.Reload(fields.FindBool("fromOrigin").value_or(false)
                          ? content::ReloadType::BYPASSING_CACHE
                          : content::ReloadType::NORMAL,
                      /*check_for_repost=*/true);
  } else if (name == "stopLoading") {
    web_contents_->Stop();
  } else if (name == "setZoom") {
    double factor = fields.FindDouble("factor").value_or(1.0);
    if (auto* zoom = zoom::ZoomController::FromWebContents(web_contents_.get())) {
      zoom->SetZoomLevel(blink::ZoomFactorToZoomLevel(factor));
      Emit("zoomChanged", base::DictValue().Set("factor", factor));
    }
  } else if (name == "setAudioMuted") {
    web_contents_->SetAudioMuted(fields.FindBool("muted").value_or(false));
  } else if (name == "setVisibility") {
    const std::string* visibility = fields.FindString("visibility");
    const bool visible = visibility && *visibility == "visible";
    if (attached_) {
      hostable_view()->ViewsHostableSetVisible(visible);
    }
    visible ? web_contents_->WasShown() : web_contents_->WasHidden();
  } else if (name == "focus") {
    if (attached_) {
      hostable_view()->ViewsHostableMakeFirstResponder();
    }
  } else if (name == "terminateRenderer") {
    renderer_termination_requested_ = true;
    web_contents_->GetPrimaryMainFrame()->GetProcess()->Shutdown(
        content::RESULT_CODE_KILLED);
  }
  // find, stopFinding, devTools, setMediaSuspended and cancelDownload are not declared in
  // the engine's capabilities yet, so Refrax does not send them.
}

void HostPage::EvaluateScript(const std::string& request,
                              EvaluateScriptCallback callback) {
  std::optional<base::Value> parsed =
      base::JSONReader::Read(request, base::JSON_PARSE_RFC);
  const base::DictValue* fields = parsed ? parsed->GetIfDict() : nullptr;
  const std::string* source = fields ? fields->FindString("source") : nullptr;
  const base::DictValue* world = fields ? fields->FindDict("world") : nullptr;
  if (!source || !world) {
    receiver_.ReportBadMessage("EvaluateScript: malformed request");
    return;
  }
  std::optional<int32_t> world_id = engine_->worlds().WorldID(*world);
  if (!world_id) {
    receiver_.ReportBadMessage("EvaluateScript: unknown world");
    return;
  }
  // The renderer runs it (//refrax/renderer/frame_scripts.cc): content's browser-side script
  // APIs only reach content's own worlds and never await promises.
  mojo::AssociatedRemote<mojom::FrameScripts> frame_scripts;
  web_contents_->GetPrimaryMainFrame()->GetRemoteAssociatedInterfaces()->GetInterface(
      &frame_scripts);
  mojom::FrameScripts* evaluator = frame_scripts.get();
  evaluator->Evaluate(
      *source, *world_id, fields->FindBool("userGesture").value_or(false),
      base::BindOnce(
          [](mojo::AssociatedRemote<mojom::FrameScripts>, EvaluateScriptCallback callback,
             std::optional<base::Value> result, const std::optional<std::string>& error) {
            if (error) {
              std::move(callback).Run(std::nullopt, *error);
              return;
            }
            std::move(callback).Run(
                result ? base::WriteJson(*result).value_or("null") : "null",
                std::nullopt);
          },
          std::move(frame_scripts), std::move(callback)));
}

void HostPage::Close() {
  // Deletes this.
  engine_->DestroyPage(this);
}

// MARK: ui::ViewsHostableView::Host

ui::Layer* HostPage::GetUiLayer() const {
  // No compositor on the host side: each RenderWidgetHostView composites on its own and ships
  // CALayerParams to its NSView in the client.
  return nullptr;
}

remote_cocoa::mojom::Application* HostPage::GetRemoteCocoaApplication() const {
  return engine_->application();
}

uint64_t HostPage::GetNSViewId() const {
  return container_ns_view_id_;
}

void HostPage::OnHostableViewDestroying() {
  attached_ = false;
}

// MARK: content::WebContentsObserver

void HostPage::DidStartNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame() || navigation->IsSameDocument()) {
    return;
  }
  Emit("navigationStarted",
       base::DictValue().Set("url", contract::URLValue(navigation->GetURL())));
}

void HostPage::DidRedirectNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame()) {
    return;
  }
  Emit("navigationRedirected",
       base::DictValue().Set("url", contract::URLValue(navigation->GetURL())));
}

void HostPage::DidFinishNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame()) {
    return;
  }
  const GURL& url = navigation->GetURL();
  const int error = navigation->GetNetErrorCode();
  if (error != net::OK) {
    Emit("navigationFailed",
         base::DictValue().Set(
             "failure", base::DictValue()
                            .Set("kind", FailureKind(error))
                            .Set("url", contract::URLValue(url))
                            .Set("isProvisional", true)
                            .Set("engineCode", error)
                            .Set("description", net::ErrorToShortString(error))));
  }
  if (navigation->HasCommitted()) {
    if (!navigation->IsSameDocument() && !navigation->IsErrorPage()) {
      Emit("navigationCommitted",
           base::DictValue()
               .Set("url", contract::URLValue(url))
               .Set("isBackForward",
                    (navigation->GetPageTransition() &
                     ui::PAGE_TRANSITION_FORWARD_BACK) != 0));
    }
    Emit("urlChanged", base::DictValue().Set(
                           "url", contract::URLValue(
                                      web_contents_->GetLastCommittedURL())));
  }
  EmitBackForward();
}

void HostPage::DidStartLoading() {
  Emit("loadingChanged", base::DictValue().Set("isLoading", true));
}

void HostPage::DidStopLoading() {
  Emit("loadingChanged", base::DictValue().Set("isLoading", false));
}

void HostPage::LoadProgressChanged(double progress) {
  Emit("progressChanged", base::DictValue().Set("progress", progress));
}

void HostPage::DidFinishLoad(content::RenderFrameHost* frame,
                             const GURL& validated_url) {
  if (!frame->IsInPrimaryMainFrame()) {
    return;
  }
  base::DictValue fields;
  fields.Set("url", contract::URLValue(validated_url));
  if (content::NavigationEntry* entry =
          web_contents_->GetController().GetLastCommittedEntry()) {
    if (int status = entry->GetHttpStatusCode()) {
      fields.Set("statusCode", status);
    }
  }
  Emit("navigationFinished", std::move(fields));
}

void HostPage::TitleWasSet(content::NavigationEntry* entry) {
  Emit("titleChanged",
       base::DictValue().Set("title", base::UTF16ToUTF8(web_contents_->GetTitle())));
}

void HostPage::DidUpdateFaviconURL(
    content::RenderFrameHost* frame,
    const std::vector<blink::mojom::FaviconURLPtr>& candidates,
    blink::mojom::FaviconUpdateReason reason) {
  if (!frame->IsInPrimaryMainFrame()) {
    return;
  }
  base::ListValue urls;
  for (const auto& candidate : candidates) {
    if (candidate->icon_url.is_valid()) {
      urls.Append(candidate->icon_url.spec());
    }
  }
  Emit("faviconsChanged", base::DictValue().Set("urls", std::move(urls)));
}

void HostPage::PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) {
  const std::string_view reason =
      TerminationReason(status, renderer_termination_requested_);
  renderer_termination_requested_ = false;
  Emit("rendererHealthChanged",
       base::DictValue().Set(
           "health", base::DictValue().Set(
                         "terminated", base::DictValue().Set("reason", reason))));
}

void HostPage::OnRendererUnresponsive(content::RenderProcessHost* process) {
  Emit("rendererHealthChanged",
       base::DictValue().Set(
           "health",
           base::DictValue().Set(
               "unresponsive",
               base::DictValue().Set(
                   "since", base::Time::Now().InSecondsFSinceUnixEpoch()))));
}

void HostPage::OnRendererResponsive(content::RenderProcessHost* process) {
  Emit("rendererHealthChanged",
       base::DictValue().Set("health",
                             base::DictValue().Set("running", base::DictValue())));
}

// MARK: content::WebContentsDelegate

content::WebContents* HostPage::OpenURLFromTab(
    content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>
        navigation_handle_callback) {
  if (params.disposition == WindowOpenDisposition::CURRENT_TAB) {
    base::WeakPtr<content::NavigationHandle> navigation =
        source->GetController().LoadURLWithParams(
            content::NavigationController::LoadURLParams(params));
    if (navigation && navigation_handle_callback) {
      std::move(navigation_handle_callback).Run(*navigation);
    }
    return source;
  }
  RequestOpenURL(params.url, params.disposition, params.user_gesture);
  return nullptr;
}

content::WebContents* HostPage::AddNewContents(
    content::WebContents* source,
    std::unique_ptr<content::WebContents> new_contents,
    const GURL& target_url,
    WindowOpenDisposition disposition,
    const blink::mojom::WindowFeatures& window_features,
    bool user_gesture,
    bool* was_blocked) {
  // Refrax opens the URL in a page of its own; the opener relationship to this page is not
  // kept, so `new_contents` is dropped.
  RequestOpenURL(target_url, disposition, user_gesture);
  return nullptr;
}

void HostPage::UpdateTargetURL(content::WebContents* source, const GURL& url) {
  Emit("hoveredLinkChanged",
       base::DictValue().Set("url", contract::URLValue(url)));
}

}  // namespace refrax
