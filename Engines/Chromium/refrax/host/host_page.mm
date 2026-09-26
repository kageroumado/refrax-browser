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
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "components/zoom/zoom_controller.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/result_codes.h"
#include "components/input/native_web_keyboard_event.h"
#include "net/base/net_errors.h"
#include "ui/events/cocoa/cocoa_event_utils.h"
#include "refrax/host/contract_json.h"
#include "refrax/host/engine_host_impl.h"
#include "refrax/host/notifications.h"
#include "refrax/host/page_dialogs.h"
#include "refrax/host/page_downloads.h"
#include "refrax/host/permission_prompt.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "components/permissions/permission_request_manager.h"
#include "refrax/host/page_scripts.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "third_party/blink/public/mojom/favicon/favicon_url.mojom.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/geometry/rect.h"

namespace refrax {

namespace {

// How long a snapshot may wait for the compositor.
constexpr base::TimeDelta kSnapshotTimeout = base::Seconds(5);

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
  // The client is gone: nobody waits for a reply.
  receiver_.set_disconnect_handler(
      base::BindOnce(&HostPage::Close, base::Unretained(this), base::DoNothing()));
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
  dialogs_ = std::make_unique<PageDialogs>(base::BindRepeating(
      &HostPage::SendRequest, weak_factory_.GetWeakPtr()));
  downloads_ = std::make_unique<PageDownloads>(
      base::BindRepeating(&HostPage::SendRequest, weak_factory_.GetWeakPtr()),
      base::BindRepeating(
          [](base::WeakPtr<HostPage> page, std::string_view name, base::DictValue fields) {
            if (page) {
              page->Emit(name, std::move(fields));
            }
          },
          weak_factory_.GetWeakPtr()));
  // Permission questions go to Refrax instead of Chrome's bubbles.
  permissions::PermissionRequestManager::FromWebContents(web_contents_.get())
      ->set_view_factory(PermissionPrompt::Factory(
          base::BindRepeating(&HostPage::SendRequest, weak_factory_.GetWeakPtr())));
}

void HostPage::AskForDownload(
    download::DownloadItem* download,
    const base::FilePath& suggested_path,
    DownloadTargetDeterminerDelegate::ConfirmationCallback callback) {
  downloads_->Ask(download, suggested_path, std::move(callback));
}

void HostPage::ApplyScripts(const base::ListValue& scripts) {
  scripts_->Apply(scripts);
}

HostPage::~HostPage() {
  downloads_.reset();
  dialogs_.reset();
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

void HostPage::SendRequest(std::string request,
                           base::OnceCallback<void(const std::string&)> answer) {
  client_->OnRequest(request, std::move(answer));
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

  // A dialog holds its renderer inside alert()/confirm() until answered, and a navigation that
  // commits in that renderer waits on it forever. Navigating dismisses the page's questions
  // (CONTRACT.md §4.3), so they are answered `cancel` first.
  if (name == "load" || name == "goBack" || name == "goForward" || name == "reload") {
    dialogs_->CancelDialogs(web_contents_.get(), /*reset_state=*/false);
  }

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
    zoom_factor_ = fields.FindDouble("factor").value_or(1.0);
    ApplyZoom();
    Emit("zoomChanged", base::DictValue().Set("factor", zoom_factor_));
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
    // The container first, then the renderer's own view inside it: Chrome's focus manager
    // follows the first with WebContents::Focus, and keystrokes go to the second.
    if (attached_) {
      hostable_view()->ViewsHostableMakeFirstResponder();
    }
    web_contents_->Focus();
  } else if (name == "cancelDownload") {
    if (const std::string* id = fields.FindString("id")) {
      downloads_->Cancel(*id);
    }
  } else if (name == "notificationClicked" || name == "notificationClosed") {
    if (const std::string* id = fields.FindString("id")) {
      name == "notificationClicked" ? Notifications::Get().Click(*id)
                                    : Notifications::Get().Dismiss(*id);
    }
  } else if (name == "terminateRenderer") {
    renderer_termination_requested_ = true;
    web_contents_->GetPrimaryMainFrame()->GetProcess()->Shutdown(
        content::RESULT_CODE_KILLED);
  }
  // find, stopFinding, devTools and setMediaSuspended are not declared in
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
                result ? contract::Serialize(*result) : "null",
                std::nullopt);
          },
          std::move(frame_scripts), std::move(callback)));
}

void HostPage::Snapshot(const gfx::Rect& rect, SnapshotCallback callback) {
  content::RenderWidgetHostView* view = web_contents_->GetRenderWidgetHostView();
  if (!view || !view->IsSurfaceAvailableForCopy()) {
    std::move(callback).Run(SkBitmap());
    return;
  }
  view->CopyFromSurface(
      rect, gfx::Size(), kSnapshotTimeout,
      base::BindOnce(
          [](SnapshotCallback callback, const content::CopyFromSurfaceResult& result) {
            if (!result.has_value() || result->bitmap.drawsNothing()) {
              // An empty bitmap is the mojom's null.
              std::move(callback).Run(SkBitmap());
              return;
            }
            std::move(callback).Run(result->bitmap);
          },
          std::move(callback)));
}

void HostPage::Close(CloseCallback callback) {
  // Answered while the receiver still exists; the teardown's own messages follow the reply.
  std::move(callback).Run();
  engine_->DestroyPage(this);  // Deletes this.
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

void HostPage::ApplyZoom() {
  // Zoom belongs to the page and comes only from Refrax. Chrome's default mode shares one level
  // across a host's pages and saves it in the profile, and ZoomController drops back to that
  // mode on every new document, so the page is isolated again after each one.
  auto* zoom = zoom::ZoomController::FromWebContents(web_contents_.get());
  if (!zoom) {
    return;
  }
  zoom->SetZoomMode(zoom::ZoomController::ZOOM_MODE_ISOLATED);
  zoom->SetZoomLevel(blink::ZoomFactorToZoomLevel(zoom_factor_));
}

void HostPage::DidFinishNavigation(content::NavigationHandle* navigation) {
  if (!navigation->IsInPrimaryMainFrame()) {
    return;
  }
  if (navigation->HasCommitted() && !navigation->IsSameDocument()) {
    ApplyZoom();
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

content::JavaScriptDialogManager* HostPage::GetJavaScriptDialogManager(
    content::WebContents* source) {
  return dialogs_.get();
}

void HostPage::RequestMediaAccessPermission(content::WebContents* web_contents,
                                            const content::MediaStreamRequest& request,
                                            content::MediaResponseCallback callback) {
  // Chrome's media dispatcher asks through the page's PermissionRequestManager, which
  // Refrax's PermissionPrompt answers.
  MediaCaptureDevicesDispatcher::GetInstance()->ProcessMediaAccessRequest(
      web_contents, request, std::move(callback), /*extension=*/nullptr);
}

bool HostPage::CheckMediaAccessPermission(content::RenderFrameHost* render_frame_host,
                                          const url::Origin& security_origin,
                                          blink::mojom::MediaStreamType type) {
  return MediaCaptureDevicesDispatcher::GetInstance()->CheckMediaAccessPermission(
      render_frame_host, security_origin, type, /*extension=*/nullptr);
}

bool HostPage::HandleKeyboardEvent(content::WebContents* source,
                                   const input::NativeWebKeyboardEvent& event) {
  // The page didn't want it; Refrax's menus get it next, as AppKit would have offered it.
  if (event.skip_if_unhandled || !event.os_event ||
      event.os_event.Get().type != NSEventTypeKeyDown) {
    return false;
  }
  client_->RedispatchKeyEvent(ui::EventToData(event.os_event.Get()));
  return true;
}

void HostPage::UpdateTargetURL(content::WebContents* source, const GURL& url) {
  Emit("hoveredLinkChanged",
       base::DictValue().Set("url", contract::URLValue(url)));
}

}  // namespace refrax
