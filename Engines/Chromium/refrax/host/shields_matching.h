// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_SHIELDS_MATCHING_H_
#define REFRAX_HOST_SHIELDS_MATCHING_H_

#include <cstdint>
#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/values.h"
#include "refrax/host/shields_service.h"
#include "services/network/public/mojom/fetch_api.mojom-shared.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace refrax::shields {

// One request as adblock-rust sees it.
struct Request {
  Request();
  Request(const Request&);
  Request& operator=(const Request&);
  ~Request();

  GURL url;
  // adblock-rust's request type ("script", "sub_frame", …).
  std::string type;
  std::string method;
  // The document that made the request; for a main-frame navigation, the URL itself.
  GURL source;
  // The URL of the frame the request belongs to, for the log.
  GURL frame_url;
};

// adblock-rust's request type for a fetch destination.
std::string RequestType(network::mojom::RequestDestination destination,
                        bool is_outermost_main_frame,
                        bool keepalive);

// What to do with one request, copied out of ShieldsDecision.
struct Decision {
  Decision();
  Decision(Decision&&);
  Decision& operator=(Decision&&);
  ~Decision();

  bool matched = false;
  bool excepted = false;
  bool important = false;
  bool should_block = false;
  int32_t rule_source_index = -1;
  int32_t rule_line = -1;
  // A data: URL served instead of the blocked resource.
  std::string redirect;
  // The URL to load instead ($removeparam).
  GURL rewritten_url;
  std::string rule;
  std::string exception_rule;
};

// Decides `request` with `engine`. Thread-safe; takes microseconds, but a rule's
// first regex compiles for milliseconds, so the UI thread posts it (MatchOnPool).
Decision Match(const ShieldsEngineRef& engine, const Request& request);

// Matches on the thread pool and replies on the calling sequence.
void MatchOnPool(scoped_refptr<ShieldsEngineRef> engine,
                 Request request,
                 base::OnceCallback<void(Decision)> reply);

// The CSP directives $csp rules add to a document or subdocument response, or "".
std::string CspDirectives(const ShieldsEngineRef& engine, const Request& request);

// The request log's entry for a decision (shields-architecture §7): `decision` names what
// happened (blocked, redirected, rewritten, allowed, excepted, csp).
base::DictValue LogEntry(const ShieldsEngineRef& engine,
                         const Request& request,
                         const Decision& decision,
                         std::string_view what);

// The log's name for a decision: blocked, redirected, rewritten, excepted or allowed.
std::string_view DecisionName(const Decision& decision);

}  // namespace refrax::shields

#endif  // REFRAX_HOST_SHIELDS_MATCHING_H_
