// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.
//
// Refrax Shields: one adblock-rust (0.13.3) core for both engines.
//
//   Refrax.app (Swift)         parses filter lists, builds the engine, writes the DAT, exports
//                              WebKit content rules, answers the request logger.
//   Chromium host (C++)        loads the app's DAT and matches requests and cosmetics.
//
// Implemented in src/lib.rs; the two files change together (SHIELDS_ABI_VERSION).
//
// Conventions
// - Strings passed in as `const char *` are NUL-terminated UTF-8. Filter lists, DATs and JSON
//   are passed as pointer + length and need no terminator.
// - Everything returned in a ShieldsBuffer or ShieldsDecision is owned by the caller and
//   released with shields_buffer_free / shields_decision_free. Output parameters are
//   overwritten without being released first.
// - A ShieldsEngine is immutable once built or deserialized and may be queried from any number
//   of threads at once. shields_engine_use_resources is the one mutation; call it before the
//   handle is shared.
// - Every function catches internal panics and returns SHIELDS_PANIC (or NULL).

#ifndef REFRAX_SHIELDS_H_
#define REFRAX_SHIELDS_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SHIELDS_ABI_VERSION 1

typedef int32_t ShieldsStatus;
#define SHIELDS_OK 0
// A required pointer was NULL, text was not UTF-8, an enum value was out of range, or the
// operation needs a debug filter set.
#define SHIELDS_INVALID_ARGUMENT 1
// The request or source URL has no parseable host.
#define SHIELDS_INVALID_URL 2
// A DAT or JSON input was rejected.
#define SHIELDS_INVALID_DATA 3
// The library was built without the feature this call needs.
#define SHIELDS_UNSUPPORTED 4
#define SHIELDS_PANIC 5

typedef uint32_t ShieldsListFormat;
// Adblock Plus / uBlock Origin syntax.
#define SHIELDS_LIST_FORMAT_STANDARD 0
// Hosts-file syntax: every host becomes `||host^`.
#define SHIELDS_LIST_FORMAT_HOSTS 1

// Library-owned bytes. `data` is NULL when empty.
typedef struct ShieldsBuffer {
  uint8_t *data;
  size_t len;
  size_t capacity;
} ShieldsBuffer;

// Releases `buffer`'s bytes and resets it to empty. NULL and empty buffers are fine.
void shields_buffer_free(ShieldsBuffer *buffer);

// SHIELDS_ABI_VERSION of the linked library; refuse to run on a mismatch.
uint32_t shields_abi_version(void);

// Static string naming the DAT format, e.g. "adblock-0.13.3;shields-1". A DAT is readable only
// by a library reporting the same string, so it belongs in every DAT cache key.
const char *shields_engine_format(void);

// MARK: Filter sets

typedef struct ShieldsFilterSet ShieldsFilterSet;

// A new, empty set. `debug` keeps each filter's original line, which the request logger
// (ShieldsDecision.rule) and shields_filter_set_to_webkit_rules need; it enlarges the DAT.
ShieldsFilterSet *shields_filter_set_new(bool debug);

void shields_filter_set_free(ShieldsFilterSet *set);

// Adds one list's full text. Lines that fail to parse are skipped. `permissions` is adblock's
// PermissionMask (0 for downloaded lists; trusted lists get the bits their scriptlets require).
// `out_source_index`, if not NULL, receives the list's index, which ShieldsDecision reports as
// rule_source_index; lists are numbered in the order they are added, from 0.
ShieldsStatus shields_filter_set_add_list(ShieldsFilterSet *set,
                                          const uint8_t *text,
                                          size_t text_len,
                                          ShieldsListFormat format,
                                          uint8_t permissions,
                                          uint32_t *out_source_index);

// Converts the set to Apple content-blocker rules with adblock-rust's converter:
//   {"rules": [<WKContentRuleList rule>...], "convertedFilterCount": <int>}
// Rules are ordered so ignore-previous-rules follow what they except. Filters the format
// cannot express ($redirect, $removeparam, $csp, full regexes, scriptlets, procedural
// cosmetics) are omitted. The set must be a debug set (else SHIELDS_INVALID_ARGUMENT) and
// stays usable. SHIELDS_UNSUPPORTED without the `content-blocking` feature.
ShieldsStatus shields_filter_set_to_webkit_rules(const ShieldsFilterSet *set,
                                                 ShieldsBuffer *out_json);

// MARK: Engines

typedef struct ShieldsEngine ShieldsEngine;

// Compiles every list in `set` into a new engine; NULL on failure. The set is unchanged.
ShieldsEngine *shields_engine_build(const ShieldsFilterSet *set);

// Loads a DAT written by shields_engine_serialize; NULL if it is corrupt or from another
// shields_engine_format(). The bytes are copied and verified; the caller keeps ownership.
ShieldsEngine *shields_engine_deserialize(const uint8_t *dat, size_t dat_len);

// The engine's rules as a DAT. Redirect and scriptlet resources are not part of it.
ShieldsStatus shields_engine_serialize(const ShieldsEngine *engine, ShieldsBuffer *out_dat);

// Replaces the engine's redirect and scriptlet resources with a JSON array of adblock-rust
// Resource objects ({"name", "aliases", "kind", "content" (base64), "dependencies",
// "permission"}). Must not run concurrently with any other call on `engine`.
ShieldsStatus shields_engine_use_resources(ShieldsEngine *engine,
                                           const uint8_t *json,
                                           size_t json_len);

void shields_engine_free(ShieldsEngine *engine);

// MARK: Network requests

// How to handle one request. Apply in this order:
//   1. should_block and redirect non-empty: answer with the redirect resource (a data: URL)
//      instead of loading.
//   2. should_block: cancel (net::ERR_BLOCKED_BY_CLIENT on Chromium).
//   3. rewritten_url non-empty: load that URL instead ($removeparam).
//   4. Otherwise load normally.
// matched/excepted/rule/exception_rule explain the decision to the logger. rule and
// exception_rule hold the original filter text only for engines built from a debug set, and
// may be approximate where adblock-rust fused several filters into one.
typedef struct ShieldsDecision {
  bool matched;       // a blocking filter matched
  bool excepted;      // an exception (@@) matched; blocking is lifted unless important
  bool important;     // an $important filter matched; exceptions do not apply
  bool should_block;
  int32_t rule_source_index;  // the matched filter's list (shields_filter_set_add_list), or -1
  int32_t rule_line;          // its zero-based line in that list, or -1
  ShieldsBuffer redirect;       // data: URL
  ShieldsBuffer rewritten_url;
  ShieldsBuffer rule;
  ShieldsBuffer exception_rule;
} ShieldsDecision;

// Releases the decision's buffers and resets it.
void shields_decision_free(ShieldsDecision *decision);

// Decides a request from `url` of `request_type` made by a document at `source_url`.
// request_type uses webRequest names: "main_frame"/"document", "sub_frame"/"subdocument",
// "script", "stylesheet", "image", "font", "media", "object", "xmlhttprequest"/"xhr",
// "websocket", "ping", "beacon", "csp_report", "other". `method` is the HTTP method ("GET"),
// or "" when unknown. Non-http(s) URLs are allowed without matching. `out` is always written;
// on SHIELDS_INVALID_URL it is an allow.
ShieldsStatus shields_engine_check_request(const ShieldsEngine *engine,
                                           const char *url,
                                           const char *source_url,
                                           const char *request_type,
                                           const char *method,
                                           ShieldsDecision *out);

// As shields_engine_check_request, for callers that already know the hosts and whether the
// request is third-party (Chromium computes both with its own registry). Skips URL parsing.
ShieldsStatus shields_engine_check_request_preparsed(const ShieldsEngine *engine,
                                                     const char *url,
                                                     const char *hostname,
                                                     const char *source_hostname,
                                                     const char *request_type,
                                                     bool third_party,
                                                     const char *method,
                                                     ShieldsDecision *out);

// The Content-Security-Policy directives $csp filters add to this document or subdocument
// response, comma-joined; empty when none apply.
ShieldsStatus shields_engine_csp_directives(const ShieldsEngine *engine,
                                            const char *url,
                                            const char *source_url,
                                            const char *request_type,
                                            ShieldsBuffer *out);

// MARK: Cosmetic filtering

// What to apply to a document at `url` before its scripts run, as JSON:
//   {"hide_selectors": [css selector...],       hide with display:none !important
//    "procedural_actions": [json string...],    procedural/action filters for the page script
//    "exceptions": [selector...],               pass to hidden_class_id_selectors
//    "injected_script": "<js>",                 scriptlets, run in the page's main world
//    "generichide": bool}                       true: skip generic class/id hiding
ShieldsStatus shields_engine_url_cosmetic_resources(const ShieldsEngine *engine,
                                                    const char *url,
                                                    ShieldsBuffer *out_json);

// Generic hide selectors for classes and ids seen in a page. Input JSON
//   {"classes": [...], "ids": [...], "exceptions": [...]}   (exceptions from the call above)
// Output: a JSON array of selectors to hide.
ShieldsStatus shields_engine_hidden_class_id_selectors(const ShieldsEngine *engine,
                                                       const uint8_t *query_json,
                                                       size_t query_len,
                                                       ShieldsBuffer *out_json);

// MARK: Domain resolution

// Writes the byte range of `host`'s registrable domain (eTLD+1) to *start / *end, or
// 0 / host_len when it has none. `host` is not NUL-terminated. Must be thread-safe.
typedef void (*ShieldsDomainResolver)(const char *host,
                                      size_t host_len,
                                      size_t *start,
                                      size_t *end);

// Installs the process-wide resolver, once, before any engine is used. Required when the
// library is built without `embedded-domain-resolver` (the Chromium host);
// SHIELDS_UNSUPPORTED when built with it (Refrax.app). A second call returns
// SHIELDS_INVALID_ARGUMENT and keeps the first resolver.
ShieldsStatus shields_set_domain_resolver(ShieldsDomainResolver resolver);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // REFRAX_SHIELDS_H_
