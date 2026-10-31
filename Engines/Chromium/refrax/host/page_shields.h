// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_PAGE_SHIELDS_H_
#define REFRAX_HOST_PAGE_SHIELDS_H_

#include <memory>
#include <string>
#include <vector>

#include "base/memory/scoped_refptr.h"
#include "base/values.h"
#include "content/public/browser/web_contents_observer.h"
#include "mojo/public/cpp/bindings/receiver_set.h"
#include "refrax/common/mojom/engine.mojom.h"
#include "refrax/host/request_log.h"
#include "url/origin.h"

namespace refrax {

class ShieldsEngineRef;

// Refrax Shields for one page: its request log, and the cosmetic half (shields-architecture
// §4.4). As each frame of the page is about to commit a document Shields filters, the frame's
// renderer is sent what to hide and which scriptlets and procedural filters to run
// (//refrax/renderer/shields_frame_observer.cc), ahead of the commit on the same channel. The
// renderer also collects the document's classes and ids and asks back for generic hiding.
class PageShields : public content::WebContentsObserver, public mojom::ShieldsHost {
 public:
  explicit PageShields(content::WebContents* web_contents);
  PageShields(const PageShields&) = delete;
  PageShields& operator=(const PageShields&) = delete;
  ~PageShields() override;

  // Appends `entry` to the request log of the Refrax page `frame` or `web_contents` belongs
  // to; entries for other contents are dropped.
  static void LogFor(content::RenderFrameHost* frame, base::DictValue entry);
  static void LogFor(content::WebContents* web_contents, base::DictValue entry);
  // Appends a worker's `entry` to the log of a Refrax page showing the worker's origin in
  // `browser_context` (any profile when null); dropped when no page does.
  static void LogForWorker(const content::BrowserContext* browser_context,
                           const url::Origin& origin,
                           base::DictValue entry);

  RequestLog& log() { return log_; }

  // content::WebContentsObserver:
  void ReadyToCommitNavigation(content::NavigationHandle* navigation) override;

  // mojom::ShieldsHost:
  void HiddenClassIdSelectors(const std::vector<std::string>& classes,
                              const std::vector<std::string>& ids,
                              HiddenClassIdSelectorsCallback callback) override;

 private:
  // What a document's ShieldsHost answers with: the selectors its rules except from generic
  // hiding, and how much it has asked, which is bounded.
  struct Document {
    Document();
    ~Document();
    base::ListValue exceptions;
    size_t calls = 0;
    size_t names = 0;
  };

  mojo::ReceiverSet<mojom::ShieldsHost, std::unique_ptr<Document>> receivers_;
  RequestLog log_;
};

}  // namespace refrax

#endif  // REFRAX_HOST_PAGE_SHIELDS_H_
