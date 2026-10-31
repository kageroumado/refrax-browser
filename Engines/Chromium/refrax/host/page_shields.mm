// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/page_shields.h"

#include <utility>

#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
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

PageShields::PageShields(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents) {}

PageShields::~PageShields() = default;

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
  const GURL& url = navigation->GetURL();
  content::RenderFrameHost* frame = navigation->GetRenderFrameHost();
  if (!frame || !url.SchemeIsHTTPOrHTTPS()) {
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

  // Generic class/id hiding: aggressive mode only, and never under $generichide.
  mojo::PendingRemote<mojom::ShieldsHost> host;
  if (ShieldsService::Get().mode() == ShieldsService::Mode::kAggressive &&
      !resources->FindBool("generichide").value_or(false)) {
    auto document = std::make_unique<Document>();
    document->engine = engine;
    if (const base::ListValue* exceptions = resources->FindList("exceptions")) {
      document->exceptions = exceptions->Clone();
    }
    receivers_.Add(this, host.InitWithNewPipeAndPassReceiver(), std::move(document));
  }

  mojo::AssociatedRemote<mojom::ShieldsFrame> shields_frame;
  frame->GetRemoteAssociatedInterfaces()->GetInterface(&shields_frame);
  shields_frame->Apply(url, stylesheet, scriptlets ? *scriptlets : std::string(), procedural,
                       std::move(host));
}

void PageShields::HiddenClassIdSelectors(const std::vector<std::string>& classes,
                                         const std::vector<std::string>& ids,
                                         HiddenClassIdSelectorsCallback callback) {
  const std::unique_ptr<Document>& document = receivers_.current_context();
  // A renderer asks in batches; one that sends an absurd batch gets nothing.
  if (!document || classes.size() + ids.size() > 50'000) {
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
  ShieldsBuffer buffer{};
  if (shields_engine_hidden_class_id_selectors(document->engine->engine(),
                                               reinterpret_cast<const uint8_t*>(query.data()),
                                               query.size(), &buffer) != SHIELDS_OK) {
    shields_buffer_free(&buffer);
    std::move(callback).Run(std::string());
    return;
  }
  std::optional<base::Value> selectors = TakeJSON(buffer);
  std::move(callback).Run(selectors && selectors->is_list()
                              ? HidingStylesheet(selectors->GetList())
                              : std::string());
}

}  // namespace refrax
