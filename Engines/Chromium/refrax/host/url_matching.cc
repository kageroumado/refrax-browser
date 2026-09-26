// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/url_matching.h"

#include <algorithm>

#include "base/strings/strcat.h"
#include "base/strings/string_util.h"

namespace refrax::url_matching {

namespace {

// Regular expression source for `text` taken literally, escaped for a `/…/` literal.
std::string Escape(std::string_view text) {
  std::string escaped;
  for (char c : text) {
    if (std::string_view("\\/.+?^${}()|[]*").find(c) != std::string_view::npos) {
      escaped.push_back('\\');
    }
    escaped.push_back(c);
  }
  return escaped;
}

// `glob` with `*` matching any run of characters.
std::string Glob(std::string_view glob) {
  std::string regex;
  size_t start = 0;
  for (size_t star = glob.find('*'); star != std::string_view::npos;
       star = glob.find('*', start)) {
    base::StrAppend(&regex, {Escape(glob.substr(start, star - start)), ".*"});
    start = star + 1;
  }
  base::StrAppend(&regex, {Escape(glob.substr(start))});
  return regex;
}

bool IsSchemeCharacter(char c) {
  return base::IsAsciiLower(c) || base::IsAsciiDigit(c) || c == '+' || c == '-' ||
         c == '.';
}

std::optional<std::string> SchemeRegex(std::string_view scheme) {
  if (scheme == "*") {
    return "https?";
  }
  if (scheme.empty() || !base::IsAsciiLower(scheme[0])) {
    return std::nullopt;
  }
  for (char c : scheme) {
    if (!IsSchemeCharacter(c)) {
      return std::nullopt;
    }
  }
  return Escape(scheme);
}

// The host part, including how a port may follow it.
std::optional<std::string> HostRegex(std::string_view host, bool is_file) {
  if (is_file) {
    return host.empty() ? std::optional<std::string>("") : std::nullopt;
  }
  if (host.empty()) {
    return std::nullopt;
  }
  std::string_view port;
  if (size_t colon = host.rfind(':'); colon != std::string_view::npos) {
    port = host.substr(colon + 1);
    host = host.substr(0, colon);
    if (port.empty() || !std::ranges::all_of(port, base::IsAsciiDigit<char>)) {
      return std::nullopt;
    }
  }
  std::string any_port = port.empty() ? "(?::\\d+)?" : base::StrCat({":", port});
  if (host == "*") {
    return base::StrCat({"[^/:]+", any_port});
  }
  bool subdomains = host.starts_with("*.");
  if (subdomains) {
    host.remove_prefix(2);
  }
  if (host.empty() || host.find('*') != std::string_view::npos) {
    return std::nullopt;
  }
  std::string literal = Escape(base::ToLowerASCII(host));
  return base::StrCat(
      {subdomains ? "(?:[^/:]+\\.)?" : "", literal, any_port});
}

// An IP address has no parent domains: `0.1` is no suffix of `127.0.0.1` in any sense
// `domain=` means.
bool IsIPAddress(std::string_view host) {
  if (host.find(':') != std::string_view::npos || host.starts_with('[')) {
    return true;
  }
  return !host.empty() && std::ranges::all_of(host, [](char c) {
    return base::IsAsciiDigit(c) || c == '.';
  });
}

// Matches nothing: stands in for a malformed `matches` entry.
constexpr std::string_view kNever = "/(?!)/";

std::string RegexList(const std::vector<std::string>& patterns,
                      bool keep_malformed) {
  std::vector<std::string> regexes;
  for (const std::string& pattern : patterns) {
    if (std::optional<std::string> regex = MatchPatternToRegex(pattern)) {
      regexes.push_back(*regex);
    } else if (keep_malformed) {
      regexes.emplace_back(kNever);
    }
  }
  return base::StrCat({"[", base::JoinString(regexes, ","), "]"});
}

}  // namespace

bool IsAllowlistedHost(const std::set<std::string>& allowlisted,
                       std::string_view host) {
  std::string lowered = base::ToLowerASCII(host);
  if (IsIPAddress(lowered)) {
    return allowlisted.contains(lowered);
  }
  for (std::string_view candidate = lowered; !candidate.empty();) {
    if (allowlisted.contains(std::string(candidate))) {
      return true;
    }
    size_t dot = candidate.find('.');
    candidate = dot == std::string_view::npos ? std::string_view()
                                              : candidate.substr(dot + 1);
  }
  return false;
}

std::optional<std::string> MatchPatternToRegex(std::string_view pattern) {
  if (pattern == "<all_urls>") {
    return "/^(?:https?|wss?|ftp|file|urn):.*$/";
  }
  size_t separator = pattern.find("://");
  if (separator == std::string_view::npos) {
    return std::nullopt;
  }
  std::string_view scheme = pattern.substr(0, separator);
  std::string_view rest = pattern.substr(separator + 3);
  size_t slash = rest.find('/');
  if (slash == std::string_view::npos) {
    return std::nullopt;
  }
  std::optional<std::string> scheme_regex = SchemeRegex(scheme);
  std::optional<std::string> host_regex =
      HostRegex(rest.substr(0, slash), scheme == "file");
  if (!scheme_regex || !host_regex) {
    return std::nullopt;
  }
  return base::StrCat({"/^", *scheme_regex, ":\\/\\/", *host_regex,
                       Glob(rest.substr(slash)), "$/"});
}

std::string ScriptGuard(const std::vector<std::string>& matches,
                        const std::vector<std::string>& excludes) {
  return base::StrCat(
      {"(function () {\n"
       "  var url = String(location.href).split('#')[0];\n"
       "  var matches = ",
       RegexList(matches, /*keep_malformed=*/true),
       ";\n"
       "  var excludes = ",
       RegexList(excludes, /*keep_malformed=*/false),
       ";\n"
       "  var admitted = matches.length === 0;\n"
       "  for (var i = 0; i < matches.length && !admitted; i++) admitted = matches[i].test(url);\n"
       "  for (var j = 0; j < excludes.length && admitted; j++) admitted = !excludes[j].test(url);\n"
       "  return admitted;\n"
       "})()"});
}

}  // namespace refrax::url_matching
