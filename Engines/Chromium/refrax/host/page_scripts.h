// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_PAGE_SCRIPTS_H_
#define REFRAX_HOST_PAGE_SCRIPTS_H_

#include <memory>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/values.h"

namespace content {
class WebContents;
}

namespace js_injection {
class JsCommunicationHost;
}

namespace refrax {

class WorldRegistry;

// The contract's `scripts` policy for one page (Engines/CONTRACT.md §4.4): Refrax's scripts
// injected at document start or end in their worlds, and in each world a
// window.webkit.messageHandlers object holding exactly the channels granted to that world's
// scripts. Built on components/js_injection, WebView's script-injection machinery.
class PageScripts {
 public:
  // Delivers a ScriptMessage (contract JSON) to Refrax; the callback takes the ScriptReply.
  using MessageSender = base::RepeatingCallback<void(
      std::string message,
      base::OnceCallback<void(const std::string& reply)> reply)>;

  PageScripts(content::WebContents* web_contents,
              WorldRegistry* worlds,
              MessageSender sender);
  PageScripts(const PageScripts&) = delete;
  PageScripts& operator=(const PageScripts&) = delete;
  ~PageScripts();

  // Replaces the installed scripts with `scripts` (the policy's list). Applies to documents
  // loaded from now on, as WebKit's user scripts do.
  void Apply(const base::ListValue& scripts);

 private:

  void Clear();

  std::unique_ptr<js_injection::JsCommunicationHost> communication_;
  raw_ptr<WorldRegistry> worlds_;
  MessageSender sender_;
  std::vector<int> script_ids_;
  std::vector<int32_t> channel_worlds_;
};

}  // namespace refrax

#endif  // REFRAX_HOST_PAGE_SCRIPTS_H_
