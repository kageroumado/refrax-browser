// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_URL_MATCHING_H_
#define REFRAX_HOST_URL_MATCHING_H_

#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

// URL tests the contract asks of the host: allowlisted hosts for content blocking, and match
// patterns for injected scripts.
namespace refrax::url_matching {

// Whether `host` is one of `allowlisted` or a subdomain of one, as a filter list's `domain=`
// matches. `allowlisted` holds lowercase hosts; `host` may be any case.
bool IsAllowlistedHost(const std::set<std::string>& allowlisted,
                       std::string_view host);

// A JavaScript regular expression literal matching the URLs `pattern` matches, or nullopt for
// a malformed pattern. Patterns are the WebExtensions match patterns of CONTRACT.md §4.5
// (`<all_urls>`, `*://*.example.com/path*`): a `*` scheme is http or https, `*.host` also
// matches `host`, ports are ignored, and the path glob covers the path and query.
std::optional<std::string> MatchPatternToRegex(std::string_view pattern);

// JavaScript that evaluates to whether the current document's URL (without its fragment)
// passes `matches` (any of them; every URL when empty) and none of `excludes`. Malformed
// patterns match nothing: a malformed `matches` entry never admits a page, a malformed
// `excludes` entry never removes one.
std::string ScriptGuard(const std::vector<std::string>& matches,
                        const std::vector<std::string>& excludes);

}  // namespace refrax::url_matching

#endif  // REFRAX_HOST_URL_MATCHING_H_
