// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/shields_document_throttle.h"

#include <memory>
#include <string>
#include <utility>

#include "base/functional/bind.h"
#include "base/strings/escape.h"
#include "base/strings/stringprintf.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "net/base/net_errors.h"
#include "refrax/host/page_shields.h"
#include "refrax/host/shields_service.h"

namespace refrax {

namespace {

// The page a blocked document is replaced with.
std::string BlockedPage(const GURL& url, const shields::Decision& decision) {
  const std::string host = base::EscapeForHTML(url.host());
  const std::string rule =
      decision.rule.empty() ? std::string() : base::EscapeForHTML(decision.rule);
  return base::StringPrintf(
      "<!doctype html><meta charset=utf-8><meta name=color-scheme content='light dark'>"
      "<title>%s blocked</title>"
      "<style>body{font:15px -apple-system,system-ui;max-width:34em;margin:20vh auto;"
      "padding:0 2em;line-height:1.5}h1{font-size:20px;font-weight:600}"
      "code{font:13px ui-monospace,monospace;word-break:break-all}</style>"
      "<h1>Refrax Shields blocked %s</h1>"
      "<p>A content-blocking list names this site as one to block.</p>%s",
      host.c_str(), host.c_str(),
      rule.empty() ? "" : base::StringPrintf("<p>Rule: <code>%s</code></p>", rule.c_str()).c_str());
}

}  // namespace

// static
void ShieldsDocumentThrottle::MaybeAdd(content::NavigationThrottleRegistry& registry) {
  content::NavigationHandle& navigation = registry.GetNavigationHandle();
  if (!navigation.IsInOutermostMainFrame()) {
    return;
  }
  registry.AddThrottle(std::make_unique<ShieldsDocumentThrottle>(registry));
}

ShieldsDocumentThrottle::ShieldsDocumentThrottle(content::NavigationThrottleRegistry& registry)
    : content::NavigationThrottle(registry) {}

ShieldsDocumentThrottle::~ShieldsDocumentThrottle() = default;

content::NavigationThrottle::ThrottleCheckResult ShieldsDocumentThrottle::WillStartRequest() {
  return Decide();
}

content::NavigationThrottle::ThrottleCheckResult
ShieldsDocumentThrottle::WillRedirectRequest() {
  return Decide();
}

const char* ShieldsDocumentThrottle::GetNameForLogging() {
  return "RefraxShieldsDocumentThrottle";
}

content::NavigationThrottle::ThrottleCheckResult ShieldsDocumentThrottle::Decide() {
  const GURL& url = navigation_handle()->GetURL();
  if (!ShieldsService::Get().IsActiveFor(url)) {
    return PROCEED;
  }
  scoped_refptr<ShieldsEngineRef> engine = ShieldsService::Get().engine();
  if (!engine) {
    return PROCEED;
  }
  shields::Request request;
  request.url = url;
  request.source = url;
  request.frame_url = url;
  request.type = "main_frame";
  request.method = navigation_handle()->IsPost() ? "POST" : "GET";
  shields::MatchOnPool(
      engine, ShieldsService::Get().mode(), request,
      base::BindOnce(&ShieldsDocumentThrottle::OnDecided, weak_factory_.GetWeakPtr(), request));
  return DEFER;
}

void ShieldsDocumentThrottle::OnDecided(shields::Request request, shields::Decision decision) {
  if (!decision.should_block) {
    Resume();
    return;
  }
  if (scoped_refptr<ShieldsEngineRef> engine = ShieldsService::Get().engine()) {
    PageShields::LogFor(navigation_handle()->GetWebContents(),
                        shields::LogEntry(*engine, request, decision, "blocked"));
  }
  CancelDeferredNavigation(ThrottleCheckResult(BLOCK_REQUEST, net::ERR_BLOCKED_BY_CLIENT,
                                               BlockedPage(request.url, decision)));
}

}  // namespace refrax
