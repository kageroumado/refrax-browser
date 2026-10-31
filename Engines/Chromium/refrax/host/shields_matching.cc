// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/shields_matching.h"

#include <string_view>
#include <utility>

#include "base/functional/bind.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "refrax/host/contract_json.h"

namespace refrax::shields {

namespace {

std::string TakeString(ShieldsBuffer& buffer) {
  if (!buffer.data || !buffer.len) {
    return std::string();
  }
  return std::string(reinterpret_cast<const char*>(buffer.data), buffer.len);
}

bool IsThirdParty(const GURL& url, const GURL& source) {
  return !net::registry_controlled_domains::SameDomainOrHost(
      url, source, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
}

}  // namespace

Request::Request() = default;
Request::Request(const Request&) = default;
Request& Request::operator=(const Request&) = default;
Request::~Request() = default;

Decision::Decision() = default;
Decision::Decision(Decision&&) = default;
Decision& Decision::operator=(Decision&&) = default;
Decision::~Decision() = default;

std::string RequestType(network::mojom::RequestDestination destination,
                        bool is_outermost_main_frame,
                        bool keepalive) {
  using network::mojom::RequestDestination;
  switch (destination) {
    case RequestDestination::kDocument:
      return is_outermost_main_frame ? "main_frame" : "sub_frame";
    case RequestDestination::kIframe:
    case RequestDestination::kFrame:
    case RequestDestination::kFencedframe:
      return "sub_frame";
    case RequestDestination::kScript:
    case RequestDestination::kWorker:
    case RequestDestination::kSharedWorker:
    case RequestDestination::kServiceWorker:
    case RequestDestination::kAudioWorklet:
    case RequestDestination::kPaintWorklet:
      return "script";
    case RequestDestination::kStyle:
    case RequestDestination::kXslt:
      return "stylesheet";
    case RequestDestination::kImage:
      return "image";
    case RequestDestination::kFont:
      return "font";
    case RequestDestination::kAudio:
    case RequestDestination::kVideo:
    case RequestDestination::kTrack:
      return "media";
    case RequestDestination::kObject:
    case RequestDestination::kEmbed:
      return "object";
    case RequestDestination::kReport:
      return "csp_report";
    case RequestDestination::kEmpty:
      // fetch() and XMLHttpRequest; a keepalive request is a beacon or a keepalive ping.
      return keepalive ? "ping" : "xmlhttprequest";
    default:
      return "other";
  }
}

Decision Match(const ShieldsEngineRef& engine,
               ShieldsService::Mode mode,
               const Request& request) {
  Decision decision;
  if (!engine.engine() || !request.url.SchemeIsHTTPOrHTTPS()) {
    return decision;
  }
  const GURL& source = request.source.is_valid() ? request.source : request.url;
  const bool third_party = IsThirdParty(request.url, source);
  const std::string host(request.url.host());
  const std::string source_host(source.host());
  ShieldsDecision result{};
  if (shields_engine_check_request_preparsed(engine.engine(), request.url.spec().c_str(),
                                             host.c_str(), source_host.c_str(),
                                             request.type.c_str(), third_party,
                                             request.method.c_str(), &result) != SHIELDS_OK) {
    shields_decision_free(&result);
    return decision;
  }
  decision.matched = result.matched;
  decision.excepted = result.excepted;
  decision.important = result.important;
  decision.should_block = result.should_block;
  decision.rule_source_index = result.rule_source_index;
  decision.rule_line = result.rule_line;
  decision.redirect = TakeString(result.redirect);
  const std::string rewritten = TakeString(result.rewritten_url);
  if (!rewritten.empty()) {
    GURL url(rewritten);
    if (url.is_valid() && url != request.url) {
      decision.rewritten_url = std::move(url);
    }
  }
  decision.rule = TakeString(result.rule);
  decision.exception_rule = TakeString(result.exception_rule);
  shields_decision_free(&result);

  // Standard mode spares a site's own requests unless the rule is $important; a main-frame
  // request is always the site's own, and only $document rules match it.
  if (mode == ShieldsService::Mode::kStandard && !third_party &&
      request.type != "main_frame" && !decision.important &&
      (decision.should_block || decision.rewritten_url.is_valid())) {
    decision.should_block = false;
    decision.redirect.clear();
    decision.rewritten_url = GURL();
    decision.spared_first_party = true;
  }
  if (!decision.should_block) {
    decision.redirect.clear();
  }
  return decision;
}

void MatchOnPool(scoped_refptr<ShieldsEngineRef> engine,
                 ShieldsService::Mode mode,
                 Request request,
                 base::OnceCallback<void(Decision)> reply) {
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::TaskPriority::USER_BLOCKING},
      base::BindOnce(
          [](scoped_refptr<ShieldsEngineRef> engine, ShieldsService::Mode mode,
             Request request) { return Match(*engine, mode, request); },
          std::move(engine), mode, std::move(request)),
      std::move(reply));
}

std::string CspDirectives(const ShieldsEngineRef& engine, const Request& request) {
  if (!engine.engine() || !request.url.SchemeIsHTTPOrHTTPS()) {
    return std::string();
  }
  const GURL& source = request.source.is_valid() ? request.source : request.url;
  ShieldsBuffer buffer{};
  if (shields_engine_csp_directives(engine.engine(), request.url.spec().c_str(),
                                    source.spec().c_str(), request.type.c_str(),
                                    &buffer) != SHIELDS_OK) {
    shields_buffer_free(&buffer);
    return std::string();
  }
  std::string csp = TakeString(buffer);
  shields_buffer_free(&buffer);
  return csp;
}

std::string_view DecisionName(const Decision& decision) {
  if (decision.should_block) {
    return decision.redirect.empty() ? "blocked" : "redirected";
  }
  if (decision.rewritten_url.is_valid()) {
    return "rewritten";
  }
  if (decision.excepted && decision.matched) {
    return "excepted";
  }
  return "allowed";
}

base::DictValue LogEntry(const ShieldsEngineRef& engine,
                         const Request& request,
                         const Decision& decision,
                         std::string_view what) {
  base::DictValue entry;
  entry.Set("time", base::Time::Now().InSecondsFSinceUnixEpoch());
  entry.Set("frameURL", contract::URLValue(request.frame_url));
  entry.Set("url", contract::URLValue(request.url));
  entry.Set("type", request.type);
  entry.Set("method", request.method.empty() ? "GET" : request.method);
  entry.Set("decision", what);
  if (!decision.rule.empty()) {
    entry.Set("rule", decision.rule);
  }
  if (std::optional<std::string> list = engine.ListID(decision.rule_source_index)) {
    entry.Set("list", *list);
  }
  if (decision.rule_line >= 0) {
    entry.Set("line", decision.rule_line);
  }
  if (!decision.exception_rule.empty()) {
    entry.Set("exceptionRule", decision.exception_rule);
  }
  if (decision.rewritten_url.is_valid()) {
    entry.Set("rewrittenURL", contract::URLValue(decision.rewritten_url));
  }
  if (decision.spared_first_party) {
    entry.Set("sparedFirstParty", true);
  }
  entry.Set("exactness", "exact");
  return entry;
}

}  // namespace refrax::shields
