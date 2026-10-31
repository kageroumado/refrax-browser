// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_DEVTOOLS_FRONTEND_H_
#define REFRAX_HOST_DEVTOOLS_FRONTEND_H_

#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/web_contents_delegate.h"
#include "ui/base/cocoa/views_hostable.h"
#include "ui/gfx/geometry/size.h"

class Profile;

namespace content {
class WebContents;
}

namespace remote_cocoa::mojom {
class Application;
}

namespace refrax {

// A page's DevTools: Chrome's DevTools frontend in a WebContents of its own, attached to the
// page, shown in a window the client opens in Refrax's process (the frontend's views are built
// there through remote_cocoa, as a page's are). The window is the engine's own: the contract's
// `devTools` commands show and hide it, and the page reports `devToolsChanged`.
class DevToolsFrontend : public content::WebContentsDelegate,
                         public ui::ViewsHostableView::Host {
 public:
  enum class Panel { kDefault, kConsole, kElementSelection };

  // `on_closed` runs when the frontend asks to close (its close button, or the page it
  // inspects going away); the owner then deletes this.
  DevToolsFrontend(content::WebContents* inspected,
                   remote_cocoa::mojom::Application* application,
                   uint64_t container_ns_view_id,
                   Panel panel,
                   base::OnceClosure on_closed);
  DevToolsFrontend(const DevToolsFrontend&) = delete;
  DevToolsFrontend& operator=(const DevToolsFrontend&) = delete;
  ~DevToolsFrontend() override;

  // The client registered the window's content view: build the frontend's views in it.
  void Attach();
  void SetSize(const gfx::Size& size);

  // Brings a panel forward in a frontend already open.
  void Show(Panel panel);

  uint64_t container_ns_view_id() const { return container_ns_view_id_; }

  // content::WebContentsDelegate:
  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override;

  // ui::ViewsHostableView::Host:
  ui::Layer* GetUiLayer() const override;
  remote_cocoa::mojom::Application* GetRemoteCocoaApplication() const override;
  uint64_t GetNSViewId() const override;
  void OnHostableViewDestroying() override;

 private:
  class BindingsDelegate;

  ui::ViewsHostableView* hostable_view() const;
  void OnLoaded();
  void RequestClose();

  const raw_ptr<content::WebContents> inspected_;
  const raw_ptr<remote_cocoa::mojom::Application> application_;
  const uint64_t container_ns_view_id_;
  std::unique_ptr<content::WebContents> frontend_;
  // An action for once the frontend has loaded.
  Panel pending_panel_;
  bool loaded_ = false;
  bool attached_ = false;
  gfx::Size size_;
  base::OnceClosure on_closed_;

  base::WeakPtrFactory<DevToolsFrontend> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_DEVTOOLS_FRONTEND_H_
