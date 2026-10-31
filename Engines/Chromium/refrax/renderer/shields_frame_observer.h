// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_RENDERER_SHIELDS_FRAME_OBSERVER_H_
#define REFRAX_RENDERER_SHIELDS_FRAME_OBSERVER_H_

#include <optional>
#include <string>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "mojo/public/cpp/bindings/associated_receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "refrax/common/mojom/engine.mojom.h"
#include "url/gurl.h"
#include "v8/include/v8-forward.h"

namespace refrax {

// The renderer half of Refrax Shields' cosmetic filtering (shields-architecture §4.4). The host
// pushes a document's resources before it commits. When the document element is created this
// hides with a user stylesheet (user origin and !important outrank the page's own CSS); blink
// forbids scripts at that moment, so at document start, before any of the page's scripts run,
// it runs the scriptlets in the main world and starts the procedural filters and, in aggressive
// mode, the generic class/id collector in the Shields world. Owned by its frame.
class ShieldsFrameObserver : public content::RenderFrameObserver,
                             public content::RenderFrameObserverTracker<ShieldsFrameObserver>,
                             public mojom::ShieldsFrame {
 public:
  // Attaches to `render_frame`; deletes itself with the frame.
  static void Create(content::RenderFrame* render_frame);

  ShieldsFrameObserver(const ShieldsFrameObserver&) = delete;
  ShieldsFrameObserver& operator=(const ShieldsFrameObserver&) = delete;
  ~ShieldsFrameObserver() override;

  // mojom::ShieldsFrame:
  void Apply(const GURL& url,
             const std::string& stylesheet,
             const std::string& scriptlets,
             const std::string& procedural_actions,
             mojo::PendingRemote<mojom::ShieldsHost> host) override;

  // Runs the current document's scriptlets and Shields world; called by Chrome's renderer client
  // at document start (patches/chrome-renderer-refrax-agents.patch).
  void RunScriptsAtDocumentStart();

  // content::RenderFrameObserver:
  void DidCreateDocumentElement() override;
  void OnDestruct() override;

 private:
  struct Pending {
    Pending();
    Pending(Pending&&);
    Pending& operator=(Pending&&);
    ~Pending();
    GURL url;
    std::string stylesheet;
    std::string scriptlets;
    std::string procedural_actions;
    mojo::PendingRemote<mojom::ShieldsHost> host;
  };

  explicit ShieldsFrameObserver(content::RenderFrame* render_frame);

  void StartShieldsWorld(const std::string& procedural_actions, bool collect);
  void InsertStylesheet(const std::string& css);

  // The Shields world's report(classes, ids): asks the host which of them generic rules hide.
  static void OnReport(const v8::FunctionCallbackInfo<v8::Value>& info);

  mojo::AssociatedReceiverSet<mojom::ShieldsFrame> receivers_;
  std::optional<Pending> pending_;
  // The document's resources once its stylesheet is in, until document start runs its scripts.
  std::optional<Pending> document_;
  // The current document's ShieldsHost, for generic hiding.
  mojo::Remote<mojom::ShieldsHost> host_;

  base::WeakPtrFactory<ShieldsFrameObserver> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_RENDERER_SHIELDS_FRAME_OBSERVER_H_
