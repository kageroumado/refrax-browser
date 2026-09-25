// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_PAGE_DIALOGS_H_
#define REFRAX_HOST_PAGE_DIALOGS_H_

#include <map>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/javascript_dialog_manager.h"

namespace refrax {

// A page's JavaScript dialogs (alert, confirm, prompt, beforeunload) as the contract's
// `javaScriptDialog` requests: Refrax shows them in the page's pane and answers. Engines never
// show dialog UI of their own (Engines/CONTRACT.md §4.3).
class PageDialogs : public content::JavaScriptDialogManager {
 public:
  // Sends a PageRequestKind (contract JSON); the callback takes the PageRequestAnswer.
  using RequestSender = base::RepeatingCallback<void(
      std::string request,
      base::OnceCallback<void(const std::string& answer)> answer)>;

  explicit PageDialogs(RequestSender sender);
  PageDialogs(const PageDialogs&) = delete;
  PageDialogs& operator=(const PageDialogs&) = delete;
  ~PageDialogs() override;

  // content::JavaScriptDialogManager:
  void RunJavaScriptDialog(content::WebContents* web_contents,
                           content::RenderFrameHost* render_frame_host,
                           content::JavaScriptDialogType dialog_type,
                           const std::u16string& message_text,
                           const std::u16string& default_prompt_text,
                           DialogClosedCallback callback,
                           bool* did_suppress_message) override;
  void RunBeforeUnloadDialog(content::WebContents* web_contents,
                             content::RenderFrameHost* render_frame_host,
                             bool is_reload,
                             DialogClosedCallback callback) override;
  void CancelDialogs(content::WebContents* web_contents, bool reset_state) override;

 private:
  void Ask(std::string_view kind,
           content::RenderFrameHost* frame,
           const std::u16string& message,
           const std::u16string* default_text,
           DialogClosedCallback callback);
  void OnAnswer(int id, const std::string& answer);

  RequestSender sender_;
  // Dialogs waiting on Refrax, by the id their answer carries back.
  std::map<int, DialogClosedCallback> pending_;
  int next_id_ = 1;
  base::WeakPtrFactory<PageDialogs> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_PAGE_DIALOGS_H_
