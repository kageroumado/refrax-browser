// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/page_dialogs.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/strings/utf_string_conversions.h"
#include "content/public/browser/render_frame_host.h"
#include "refrax/host/contract_json.h"
#include "url/origin.h"

namespace refrax {

namespace {

// Dialog text over this is truncated: the contract caps strings (CONTRACT.md §6).
constexpr size_t kMaximumDialogText = 2000;

std::string Capped(const std::u16string& text) {
  std::string utf8 = base::UTF16ToUTF8(text.substr(0, kMaximumDialogText));
  return utf8;
}

}  // namespace

PageDialogs::PageDialogs(RequestSender sender) : sender_(std::move(sender)) {}

PageDialogs::~PageDialogs() {
  // Pending dialogs block their renderer; answer them before going.
  CancelDialogs(nullptr, false);
}

void PageDialogs::RunJavaScriptDialog(content::WebContents* web_contents,
                                      content::RenderFrameHost* render_frame_host,
                                      content::JavaScriptDialogType dialog_type,
                                      const std::u16string& message_text,
                                      const std::u16string& default_prompt_text,
                                      DialogClosedCallback callback,
                                      bool* did_suppress_message) {
  *did_suppress_message = false;
  switch (dialog_type) {
    case content::JAVASCRIPT_DIALOG_TYPE_ALERT:
      Ask("alert", render_frame_host, message_text, nullptr, std::move(callback));
      break;
    case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
      Ask("confirm", render_frame_host, message_text, nullptr, std::move(callback));
      break;
    case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
      Ask("prompt", render_frame_host, message_text, &default_prompt_text,
          std::move(callback));
      break;
  }
}

void PageDialogs::RunBeforeUnloadDialog(content::WebContents* web_contents,
                                        content::RenderFrameHost* render_frame_host,
                                        bool is_reload,
                                        DialogClosedCallback callback) {
  // Pages can't set beforeunload text; Refrax words the question itself.
  Ask("beforeUnload", render_frame_host, std::u16string(), nullptr, std::move(callback));
}

void PageDialogs::CancelDialogs(content::WebContents* web_contents, bool reset_state) {
  std::map<int, DialogClosedCallback> pending = std::move(pending_);
  pending_.clear();
  for (auto& [id, callback] : pending) {
    std::move(callback).Run(false, std::u16string());
  }
}

void PageDialogs::Ask(std::string_view kind,
                      content::RenderFrameHost* frame,
                      const std::u16string& message,
                      const std::u16string* default_text,
                      DialogClosedCallback callback) {
  base::DictValue dialog;
  dialog.Set("kind", kind);
  dialog.Set("message", Capped(message));
  if (default_text) {
    dialog.Set("defaultText", Capped(*default_text));
  }
  if (frame) {
    const url::Origin origin = frame->GetLastCommittedOrigin();
    if (!origin.opaque()) {
      dialog.Set("origin", origin.Serialize());
    }
  }
  const int id = next_id_++;
  pending_[id] = std::move(callback);
  sender_.Run(
      contract::Message("javaScriptDialog", base::DictValue().Set("dialog", std::move(dialog))),
      base::BindOnce(&PageDialogs::OnAnswer, weak_factory_.GetWeakPtr(), id));
}

void PageDialogs::OnAnswer(int id, const std::string& answer) {
  auto it = pending_.find(id);
  if (it == pending_.end()) {
    // Cancelled meanwhile (a navigation committed, or the page closed).
    return;
  }
  DialogClosedCallback callback = std::move(it->second);
  pending_.erase(it);
  auto message = contract::ParseMessage(answer);
  if (message && message->first == "confirm") {
    const std::string* text = message->second.FindString("text");
    std::move(callback).Run(true, text ? base::UTF8ToUTF16(*text) : std::u16string());
    return;
  }
  std::move(callback).Run(false, std::u16string());
}

}  // namespace refrax
