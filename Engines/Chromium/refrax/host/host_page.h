// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_HOST_PAGE_H_
#define REFRAX_HOST_HOST_PAGE_H_

#include <memory>
#include <string>
#include <string_view>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "chrome/browser/download/download_target_determiner_delegate.h"
#include "content/public/browser/web_contents_delegate.h"
#include "content/public/browser/web_contents_observer.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "refrax/common/mojom/engine.mojom.h"
#include "ui/base/cocoa/views_hostable.h"
#include "ui/gfx/geometry/size.h"

class Profile;

namespace refrax {

class EngineHostImpl;
class PageDialogs;
class PageDownloads;
class PageScripts;

// One Refrax page: a WebContents with Chrome's tab helpers, whose views live in the client's
// container NSView (remote_cocoa, via ViewsHostableAttach). Translates the WebContents'
// callbacks into contract events and contract commands into WebContents calls.
class HostPage : public mojom::Page,
                 public content::WebContentsObserver,
                 public content::WebContentsDelegate,
                 public ui::ViewsHostableView::Host {
 public:
  HostPage(EngineHostImpl* engine,
           Profile* profile,
           std::string id,
           mojo::PendingAssociatedReceiver<mojom::Page> receiver,
           mojo::PendingAssociatedRemote<mojom::PageClient> client);
  HostPage(const HostPage&) = delete;
  HostPage& operator=(const HostPage&) = delete;
  ~HostPage() override;

  // The id the client registers its container NSView under.
  uint64_t container_ns_view_id() const { return container_ns_view_id_; }

  void Load(const GURL& url);

  // Asks Refrax where one of this page's downloads goes.
  void AskForDownload(download::DownloadItem* download,
                      const base::FilePath& suggested_path,
                      DownloadTargetDeterminerDelegate::ConfirmationCallback callback);

  content::WebContents* web_contents() const { return web_contents_.get(); }

  // Replaces the page's Refrax scripts (the contract's `scripts` policy).
  void ApplyScripts(const base::ListValue& scripts);

  // Sends the contract's PageEvent `name`.
  void Emit(std::string_view name, base::DictValue fields = {});

  base::WeakPtr<HostPage> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }

  // mojom::Page:
  void AttachView() override;
  void SetSize(const gfx::Size& size) override;
  void PerformCommand(const std::string& command) override;
  void EvaluateScript(const std::string& request,
                      EvaluateScriptCallback callback) override;
  void Snapshot(const gfx::Rect& rect, SnapshotCallback callback) override;
  void Close(CloseCallback callback) override;

  // ui::ViewsHostableView::Host:
  ui::Layer* GetUiLayer() const override;
  remote_cocoa::mojom::Application* GetRemoteCocoaApplication() const override;
  uint64_t GetNSViewId() const override;
  void OnHostableViewDestroying() override;

  // content::WebContentsObserver:
  void DidStartNavigation(content::NavigationHandle* navigation) override;
  void DidRedirectNavigation(content::NavigationHandle* navigation) override;
  void DidFinishNavigation(content::NavigationHandle* navigation) override;
  void DidStartLoading() override;
  void DidStopLoading() override;
  void LoadProgressChanged(double progress) override;
  void DidFinishLoad(content::RenderFrameHost* frame,
                     const GURL& validated_url) override;
  void TitleWasSet(content::NavigationEntry* entry) override;
  void DidUpdateFaviconURL(
      content::RenderFrameHost* frame,
      const std::vector<blink::mojom::FaviconURLPtr>& candidates,
      blink::mojom::FaviconUpdateReason reason) override;
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) override;
  void OnRendererUnresponsive(content::RenderProcessHost* process) override;
  void OnRendererResponsive(content::RenderProcessHost* process) override;

  // content::WebContentsDelegate:
  content::WebContents* OpenURLFromTab(
      content::WebContents* source,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)>
          navigation_handle_callback) override;
  content::WebContents* AddNewContents(
      content::WebContents* source,
      std::unique_ptr<content::WebContents> new_contents,
      const GURL& target_url,
      WindowOpenDisposition disposition,
      const blink::mojom::WindowFeatures& window_features,
      bool user_gesture,
      bool* was_blocked) override;
  void UpdateTargetURL(content::WebContents* source, const GURL& url) override;
  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override;
  content::JavaScriptDialogManager* GetJavaScriptDialogManager(
      content::WebContents* source) override;
  void RequestMediaAccessPermission(content::WebContents* web_contents,
                                    const content::MediaStreamRequest& request,
                                    content::MediaResponseCallback callback) override;
  bool CheckMediaAccessPermission(content::RenderFrameHost* render_frame_host,
                                  const url::Origin& security_origin,
                                  blink::mojom::MediaStreamType type) override;

 private:
  // Puts the page's zoom at zoom_factor_, in its own isolated level.
  void ApplyZoom();

  void EmitBackForward();
  // Sends a contract request to Refrax; `answer` runs with its PageRequestAnswer.
  void SendRequest(std::string request,
                   base::OnceCallback<void(const std::string&)> answer);
  void RequestOpenURL(const GURL& url,
                      WindowOpenDisposition disposition,
                      bool user_gesture);
  ui::ViewsHostableView* hostable_view() const;
  void ApplyBounds();

  raw_ptr<EngineHostImpl> engine_;
  const std::string id_;
  const uint64_t container_ns_view_id_;
  std::unique_ptr<content::WebContents> web_contents_;
  mojo::AssociatedReceiver<mojom::Page> receiver_;
  mojo::AssociatedRemote<mojom::PageClient> client_;
  std::unique_ptr<PageScripts> scripts_;
  std::unique_ptr<PageDialogs> dialogs_;
  std::unique_ptr<PageDownloads> downloads_;

  bool attached_ = false;
  // The zoom Refrax last set (1 = 100%), kept across the page's navigations as WebKit's
  // pageZoom is.
  double zoom_factor_ = 1.0;
  gfx::Size size_;
  // Set when Refrax asked for the renderer to be killed, so its exit reads as intended.
  bool renderer_termination_requested_ = false;

  base::WeakPtrFactory<HostPage> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_HOST_PAGE_H_
