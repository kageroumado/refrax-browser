// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/renderer/frame_scripts.h"

#include <utility>

#include "base/functional/bind.h"
#include "content/public/common/isolated_world_ids.h"
#include "content/public/renderer/render_frame.h"
#include "content/public/renderer/v8_value_converter.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
#include "third_party/blink/public/mojom/frame/user_activation_notification_type.mojom.h"
#include "third_party/blink/public/platform/scheduler/web_agent_group_scheduler.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"
#include "v8/include/v8-context.h"
#include "v8/include/v8-exception.h"
#include "v8/include/v8-function.h"
#include "v8/include/v8-function-callback.h"
#include "v8/include/v8-isolate.h"
#include "v8/include/v8-primitive.h"
#include "v8/include/v8-promise.h"

namespace refrax {

namespace {

std::string Describe(v8::Isolate* isolate, v8::Local<v8::Value> value) {
  v8::String::Utf8Value text(isolate, value);
  return *text ? std::string(*text, text.length()) : "The script threw.";
}

// Completes an evaluation with `value`: JSON-compatible data, with undefined as null.
void Complete(mojom::FrameScripts::EvaluateCallback callback,
              v8::Local<v8::Context> context,
              v8::Local<v8::Value> value) {
  if (value->IsUndefined()) {
    std::move(callback).Run(base::Value(), std::nullopt);
    return;
  }
  std::unique_ptr<base::Value> converted =
      content::V8ValueConverter::Create()->FromV8Value(value, context);
  if (!converted) {
    std::move(callback).Run(std::nullopt,
                            "The script's value can't be represented as JSON.");
    return;
  }
  std::move(callback).Run(std::move(*converted), std::nullopt);
}

}  // namespace

// static
void FrameScripts::Create(content::RenderFrame* render_frame) {
  new FrameScripts(render_frame);
}

FrameScripts::FrameScripts(content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame),
      content::RenderFrameObserverTracker<FrameScripts>(render_frame) {
  render_frame->GetAssociatedInterfaceRegistry()->AddInterface<mojom::FrameScripts>(
      base::BindRepeating(
          [](FrameScripts* self,
             mojo::PendingAssociatedReceiver<mojom::FrameScripts> receiver) {
            self->receivers_.Add(self, std::move(receiver));
          },
          base::Unretained(this)));
}

FrameScripts::~FrameScripts() = default;

void FrameScripts::Evaluate(const std::string& source,
                            int32_t world_id,
                            bool user_gesture,
                            EvaluateCallback callback) {
  blink::WebLocalFrame* frame = render_frame()->GetWebFrame();
  v8::Isolate* isolate = frame->GetAgentGroupScheduler()->Isolate();
  v8::HandleScope handles(isolate);
  v8::Local<v8::Context> context =
      world_id == content::ISOLATED_WORLD_ID_GLOBAL
          ? frame->MainWorldScriptContext()
          : frame->GetScriptContextFromWorldId(isolate, world_id);
  v8::Context::Scope context_scope(context);

  if (user_gesture) {
    frame->NotifyUserActivation(
        blink::mojom::UserActivationNotificationType::kInteraction);
  }
  const blink::WebScriptSource script{blink::WebString::FromUtf8(source)};
  v8::TryCatch try_catch(isolate);
  v8::Local<v8::Value> value =
      world_id == content::ISOLATED_WORLD_ID_GLOBAL
          ? frame->ExecuteScriptAndReturnValue(script)
          : frame->ExecuteScriptInIsolatedWorldAndReturnValue(
                world_id, script, blink::BackForwardCacheAware::kAllow);
  if (try_catch.HasCaught()) {
    std::move(callback).Run(std::nullopt, Describe(isolate, try_catch.Exception()));
    return;
  }
  // Blink catches a synchronous exception itself, reports it to the page's console and
  // returns no value; a script that completes with undefined returns undefined.
  if (value.IsEmpty()) {
    std::move(callback).Run(std::nullopt,
                            "The script threw an exception (reported in the page's console).");
    return;
  }
  if (!value->IsPromise()) {
    Complete(std::move(callback), context, value);
    return;
  }

  const int id = next_pending_id_++;
  pending_[id] = std::move(callback);
  v8::Local<v8::Value> data = v8::Integer::New(isolate, id);
  v8::Local<v8::Function> on_fulfilled;
  v8::Local<v8::Function> on_rejected;
  if (!v8::Function::New(context, &FrameScripts::OnPromiseFulfilled, data)
           .ToLocal(&on_fulfilled) ||
      !v8::Function::New(context, &FrameScripts::OnPromiseRejected, data)
           .ToLocal(&on_rejected) ||
      value.As<v8::Promise>()->Then(context, on_fulfilled, on_rejected).IsEmpty()) {
    EvaluateCallback failed = std::move(pending_[id]);
    pending_.erase(id);
    std::move(failed).Run(std::nullopt, "The script's promise could not be awaited.");
  }
}

// static
void FrameScripts::OnPromiseFulfilled(const v8::FunctionCallbackInfo<v8::Value>& info) {
  SettlePromise(info, /*rejected=*/false);
}

// static
void FrameScripts::OnPromiseRejected(const v8::FunctionCallbackInfo<v8::Value>& info) {
  SettlePromise(info, /*rejected=*/true);
}

// static
void FrameScripts::SettlePromise(const v8::FunctionCallbackInfo<v8::Value>& info,
                                 bool rejected) {
  v8::Isolate* isolate = info.GetIsolate();
  v8::Local<v8::Context> context = isolate->GetCurrentContext();
  // The frame may have gone, and its FrameScripts with it, while the promise was pending.
  blink::WebLocalFrame* frame = blink::WebLocalFrame::FrameForContext(context);
  content::RenderFrame* render_frame =
      frame ? content::RenderFrame::FromWebFrame(frame) : nullptr;
  FrameScripts* self = render_frame ? FrameScripts::Get(render_frame) : nullptr;
  if (!self) {
    return;
  }
  auto it = self->pending_.find(static_cast<int>(info.Data().As<v8::Integer>()->Value()));
  if (it == self->pending_.end()) {
    return;
  }
  EvaluateCallback callback = std::move(it->second);
  self->pending_.erase(it);
  v8::Local<v8::Value> value = info.Length() > 0 ? info[0] : v8::Undefined(isolate);
  if (rejected) {
    std::move(callback).Run(std::nullopt, Describe(isolate, value));
  } else {
    Complete(std::move(callback), context, value);
  }
}

void FrameScripts::OnDestruct() {
  delete this;
}

}  // namespace refrax
