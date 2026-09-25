// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_RENDERER_FRAME_SCRIPTS_H_
#define REFRAX_RENDERER_FRAME_SCRIPTS_H_

#include <map>

#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "mojo/public/cpp/bindings/associated_receiver_set.h"
#include "refrax/common/mojom/engine.mojom.h"
#include "v8/include/v8-forward.h"

namespace refrax {

// The renderer half of the contract's evaluateScript: runs a script in the frame in the world
// the host names, with a user activation only when asked for, and completes with its value as
// JSON-compatible data (a promise is awaited, undefined is null) or with the exception's
// message. Owned by its frame.
class FrameScripts : public content::RenderFrameObserver,
                     public content::RenderFrameObserverTracker<FrameScripts>,
                     public mojom::FrameScripts {
 public:
  // Attaches to `render_frame`; deletes itself with the frame.
  static void Create(content::RenderFrame* render_frame);

  FrameScripts(const FrameScripts&) = delete;
  FrameScripts& operator=(const FrameScripts&) = delete;
  ~FrameScripts() override;

  // mojom::FrameScripts:
  void Evaluate(const std::string& source,
                int32_t world_id,
                bool user_gesture,
                EvaluateCallback callback) override;

  // content::RenderFrameObserver:
  void OnDestruct() override;

 private:
  explicit FrameScripts(content::RenderFrame* render_frame);

  // Settles an evaluation whose script returned a promise.
  static void OnPromiseFulfilled(const v8::FunctionCallbackInfo<v8::Value>& info);
  static void OnPromiseRejected(const v8::FunctionCallbackInfo<v8::Value>& info);
  static void SettlePromise(const v8::FunctionCallbackInfo<v8::Value>& info,
                            bool rejected);

  mojo::AssociatedReceiverSet<mojom::FrameScripts> receivers_;
  // Evaluations waiting on a promise, by the id its settle functions carry.
  std::map<int, EvaluateCallback> pending_;
  int next_pending_id_ = 1;
};

}  // namespace refrax

#endif  // REFRAX_RENDERER_FRAME_SCRIPTS_H_
