// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/page_shields.h"

#include <set>
#include <utility>

#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/no_destructor.h"
#include "base/task/thread_pool.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "refrax/host/host_page.h"
#include "refrax/host/shields_service.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"

namespace refrax {

namespace {

std::optional<base::Value> TakeJSON(ShieldsBuffer& buffer) {
  std::optional<base::Value> value;
  if (buffer.data && buffer.len) {
    value = base::JSONReader::Read(
        std::string_view(reinterpret_cast<const char*>(buffer.data), buffer.len),
        base::JSON_PARSE_RFC);
  }
  shields_buffer_free(&buffer);
  return value;
}

// One rule per selector: an invalid selector drops only its own rule, not its neighbors'.
std::string HidingStylesheet(const base::ListValue& selectors) {
  std::string css;
  for (const base::Value& selector : selectors) {
    if (selector.is_string() && !selector.GetString().empty()) {
      css += selector.GetString();
      css += "{display:none!important}\n";
    }
  }
  return css;
}

}  // namespace

PageShields::Document::Document() = default;
PageShields::Document::~Document() = default;

// Every live PageShields, for attributing workers' requests to a page.
static std::set<PageShields*>& AllPageShields() {
  static base::NoDestructor<std::set<PageShields*>> all;
  return *all;
}

PageShields::PageShields(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents) {
  AllPageShields().insert(this);
}

PageShields::~PageShields() {
  AllPageShields().erase(this);
}

// static
void PageShields::LogForWorker(const content::BrowserContext* browser_context,
                               const url::Origin& origin,
                               base::DictValue entry) {
  for (PageShields* shields : AllPageShields()) {
    content::WebContents* contents = shields->web_contents();
    if (!contents || (browser_context && contents->GetBrowserContext() != browser_context)) {
      continue;
    }
    if (contents->GetPrimaryMainFrame()->GetLastCommittedOrigin() == origin) {
      shields->log().Add(std::move(entry));
      return;
    }
  }
}

// static
void PageShields::LogFor(content::RenderFrameHost* frame, base::DictValue entry) {
  LogFor(content::WebContents::FromRenderFrameHost(frame), std::move(entry));
}

// static
void PageShields::LogFor(content::WebContents* web_contents, base::DictValue entry) {
  HostPage* page = web_contents ? HostPage::FromWebContents(web_contents) : nullptr;
  if (page) {
    page->shields().log().Add(std::move(entry));
  }
}

void PageShields::ReadyToCommitNavigation(content::NavigationHandle* navigation) {
  if (navigation->IsSameDocument() || navigation->IsErrorPage()) {
    return;
  }
  const GURL& document_url = navigation->GetURL();
  content::RenderFrameHost* frame = navigation->GetRenderFrameHost();
  if (!frame) {
    return;
  }
  // The rules of the page that made the document: an about:blank or about:srcdoc frame, or a
  // data:, blob: or javascript: one, gets its parent's (uBO's match_about_blank), so a page
  // can't escape its scriptlets through a frame of its own.
  GURL url = document_url;
  if (!url.SchemeIsHTTPOrHTTPS()) {
    if (url.SchemeIsBlob()) {
      url = url::Origin::Create(url).GetURL();
    } else if (content::RenderFrameHost* parent = frame->GetParentOrOuterDocument()) {
      url = parent->GetLastCommittedURL();
    } else if (navigation->GetInitiatorOrigin() && !navigation->GetInitiatorOrigin()->opaque()) {
      url = navigation->GetInitiatorOrigin()->GetURL();
    }
  }
  if (!url.SchemeIsHTTPOrHTTPS()) {
    return;
  }
  const GURL top_url = navigation->IsInOutermostMainFrame()
                           ? url
                           : frame->GetOutermostMainFrame()->GetLastCommittedURL();
  if (!ShieldsService::Get().IsActiveFor(top_url)) {
    return;
  }
  scoped_refptr<ShieldsEngineRef> engine = ShieldsService::Get().engine();
  if (!engine) {
    return;
  }

  // Measured at 0.06–0.6 ms: cheaper than a thread hop, and needed before the commit.
  ShieldsBuffer buffer{};
  if (shields_engine_url_cosmetic_resources(engine->engine(), url.spec().c_str(), &buffer) !=
      SHIELDS_OK) {
    shields_buffer_free(&buffer);
    return;
  }
  std::optional<base::Value> parsed = TakeJSON(buffer);
  const base::DictValue* resources = parsed ? parsed->GetIfDict() : nullptr;
  if (!resources) {
    return;
  }

  std::string stylesheet;
  if (const base::ListValue* selectors = resources->FindList("hide_selectors")) {
    stylesheet = HidingStylesheet(*selectors);
  }
  std::string procedural = "[]";
  if (const base::ListValue* actions = resources->FindList("procedural_actions");
      actions && !actions->empty()) {
    // Each action is itself a JSON string; the renderer parses the array and then each one.
    base::JSONWriter::Write(*actions, &procedural);
  }
  const std::string* scriptlets = resources->FindString("injected_script");

  // Generic class/id hiding, except under $generichide.
  mojo::PendingRemote<mojom::ShieldsHost> host;
  if (!resources->FindBool("generichide").value_or(false)) {
    auto document = std::make_unique<Document>();
    if (const base::ListValue* exceptions = resources->FindList("exceptions")) {
      document->exceptions = exceptions->Clone();
    }
    receivers_.Add(this, host.InitWithNewPipeAndPassReceiver(), std::move(document));
  }

  mojo::AssociatedRemote<mojom::ShieldsFrame> shields_frame;
  frame->GetRemoteAssociatedInterfaces()->GetInterface(&shields_frame);
  shields_frame->Apply(document_url, stylesheet, scriptlets ? *scriptlets : std::string(),
                       procedural, std::move(host));
}

void PageShields::HiddenClassIdSelectors(const std::vector<std::string>& classes,
                                         const std::vector<std::string>& ids,
                                         HiddenClassIdSelectorsCallback callback) {
  constexpr size_t kMaxCalls = 1000;
  constexpr size_t kMaxNames = 50'000;
  Document* document = receivers_.current_context().get();
  scoped_refptr<ShieldsEngineRef> engine = ShieldsService::Get().engine();
  // A renderer asks in batches as its page grows; one that asks without end gets nothing more.
  if (!document || !engine || ++document->calls > kMaxCalls ||
      (document->names += classes.size() + ids.size()) > kMaxNames) {
    std::move(callback).Run(std::string());
    return;
  }
  base::ListValue class_list;
  for (const std::string& name : classes) {
    class_list.Append(name);
  }
  base::ListValue id_list;
  for (const std::string& name : ids) {
    id_list.Append(name);
  }
  std::string query;
  base::JSONWriter::Write(base::DictValue()
                              .Set("classes", std::move(class_list))
                              .Set("ids", std::move(id_list))
                              .Set("exceptions", document->exceptions.Clone()),
                          &query);
  // Matched off the UI thread, with the engine current when the page asks.
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::TaskPriority::USER_VISIBLE},
      base::BindOnce(
          [](scoped_refptr<ShieldsEngineRef> engine, std::string query) {
            ShieldsBuffer buffer{};
            if (shields_engine_hidden_class_id_selectors(
                    engine->engine(), reinterpret_cast<const uint8_t*>(query.data()),
                    query.size(), &buffer) != SHIELDS_OK) {
              shields_buffer_free(&buffer);
              return std::string();
            }
            std::optional<base::Value> selectors = TakeJSON(buffer);
            return selectors && selectors->is_list() ? HidingStylesheet(selectors->GetList())
                                                     : std::string();
          },
          std::move(engine), std::move(query)),
      std::move(callback));
}

}  // namespace refrax
