// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/content_blocking_compiler.h"

#include <array>
#include <cstdint>

#include "base/containers/fixed_flat_map.h"
#include "base/containers/span.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "components/subresource_filter/core/common/unindexed_ruleset.h"
#include "components/subresource_filter/tools/rule_parser/rule.h"
#include "components/subresource_filter/tools/rule_parser/rule_parser.h"
#include "components/subresource_filter/tools/ruleset_converter/rule_stream.h"
#include "crypto/hash.h"
#include "third_party/protobuf/src/google/protobuf/io/zero_copy_stream_impl_lite.h"

namespace refrax::content_blocking {

namespace {

// Part of every content version: bump it when NormalizeRule or Compile changes what a list
// compiles to, so an existing ruleset of the same lists is rebuilt.
constexpr std::string_view kFormat = "refrax2";

constexpr std::string_view kExtension = ".pb";

// Passed to DeleteUrlRuleOrAmend, which drops what the filter can't enforce (regex patterns,
// popup and non-document activation types) for any non-zero version. The ruleset is only
// read by this build.
constexpr int kLowestChromeVersion = 152;

// uBlock Origin's option spellings → Adblock Plus's, which RuleParser reads. A leading `~`
// is kept, so `~3p` becomes `~third-party`; `1p` and `first-party` carry their own `~`.
constexpr auto kOptionAliases = base::MakeFixedFlatMap<std::string_view, std::string_view>({
    {"1p", "~third-party"},
    {"3p", "third-party"},
    {"beacon", "ping"},
    {"css", "stylesheet"},
    {"doc", "document"},
    {"first-party", "~third-party"},
    {"frame", "subdocument"},
    {"from", "domain"},
    {"ghide", "generichide"},
    {"ehide", "elemhide"},
    {"img", "image"},
    {"xhr", "xmlhttprequest"},
});

std::string NormalizeOption(std::string_view option) {
  const bool inverted = option.starts_with('~');
  std::string_view name = inverted ? option.substr(1) : option;
  std::string_view value;
  if (size_t equals = name.find('='); equals != std::string_view::npos) {
    value = name.substr(equals);
    name = name.substr(0, equals);
  }
  auto alias = kOptionAliases.find(name);
  if (alias == kOptionAliases.end()) {
    return std::string(option);
  }
  std::string_view replacement = alias->second;
  if (inverted && replacement.starts_with('~')) {
    return base::StrCat({replacement.substr(1), value});
  }
  return base::StrCat({inverted ? "~" : "", replacement, value});
}

std::string ContentVersion(const std::vector<std::string>& lists) {
  crypto::hash::Hasher hasher(crypto::hash::kSha256);
  hasher.Update(kFormat);
  for (const std::string& list : lists) {
    // Length-prefixed, so moving a line from one list to the next changes the version.
    hasher.Update(base::StrCat({":", base::NumberToString(list.size()), ":"}));
    hasher.Update(list);
  }
  std::array<uint8_t, crypto::hash::kSha256Size> digest;
  hasher.Finish(digest);
  return base::StrCat(
      {kFormat, "-", base::HexEncodeLower(base::span(digest).first<12>())});
}

// The filter files every request with an empty fetch destination (fetch(), XMLHttpRequest,
// sendBeacon) as ELEMENT_TYPE_OTHER (crbug.com/373691046), so an `xhr` or `ping` rule would
// never match one. Such rules also cover OTHER.
void MatchEmptyDestination(url_pattern_index::proto::UrlRule& rule) {
  constexpr int kEmptyDestinationTypes =
      url_pattern_index::proto::ELEMENT_TYPE_XMLHTTPREQUEST |
      url_pattern_index::proto::ELEMENT_TYPE_PING;
  if (rule.element_types() & kEmptyDestinationTypes) {
    rule.set_element_types(rule.element_types() |
                           url_pattern_index::proto::ELEMENT_TYPE_OTHER);
  }
}

// The network rules of `lists` as an unindexed ruleset, or nullopt on a serialization error.
std::optional<std::string> Serialize(const std::vector<std::string>& lists) {
  std::string ruleset;
  google::protobuf::io::StringOutputStream output(&ruleset);
  subresource_filter::UnindexedRulesetWriter writer(&output);
  subresource_filter::RuleParser parser;
  for (const std::string& list : lists) {
    for (std::string_view line : base::SplitStringPiece(
             list, "\r\n", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY)) {
      if (parser.Parse(NormalizeRule(line)) !=
          url_pattern_index::proto::RULE_TYPE_URL) {
        continue;
      }
      url_pattern_index::proto::UrlRule rule = parser.url_rule().ToProtobuf();
      if (subresource_filter::DeleteUrlRuleOrAmend(&rule, kLowestChromeVersion)) {
        continue;
      }
      MatchEmptyDestination(rule);
      if (!writer.AddUrlRule(rule)) {
        return std::nullopt;
      }
    }
  }
  if (!writer.Finish()) {
    return std::nullopt;
  }
  return ruleset;
}

void DeleteOtherRulesets(const base::FilePath& directory,
                         const base::FilePath& keep) {
  base::FileEnumerator files(directory, /*recursive=*/false,
                             base::FileEnumerator::FILES);
  for (base::FilePath file = files.Next(); !file.empty(); file = files.Next()) {
    if (file != keep) {
      base::DeleteFile(file);
    }
  }
}

}  // namespace

std::string NormalizeRule(std::string_view line) {
  // Comments, cosmetic rules and scriptlets: the parser skips or rejects them as they are.
  if (line.starts_with('!') || line.starts_with('[') ||
      line.find('#') != std::string_view::npos) {
    return std::string(line);
  }
  size_t dollar = line.rfind('$');
  if (dollar == std::string_view::npos) {
    return std::string(line);
  }
  std::vector<std::string> options;
  for (std::string_view option : base::SplitStringPiece(
           line.substr(dollar + 1), ",", base::TRIM_WHITESPACE,
           base::SPLIT_WANT_NONEMPTY)) {
    options.push_back(NormalizeOption(option));
  }
  return base::StrCat(
      {line.substr(0, dollar + 1), base::JoinString(options, ",")});
}

std::optional<CompiledRuleset> Compile(const std::vector<std::string>& lists,
                                       const base::FilePath& directory) {
  if (!base::CreateDirectory(directory)) {
    return std::nullopt;
  }
  CompiledRuleset compiled;
  compiled.content_version = ContentVersion(lists);
  compiled.path =
      directory.AppendASCII(base::StrCat({compiled.content_version, kExtension}));

  if (!base::PathExists(compiled.path)) {
    std::optional<std::string> ruleset = Serialize(lists);
    if (!ruleset) {
      return std::nullopt;
    }
    base::FilePath partial = compiled.path.AddExtensionASCII("partial");
    if (!base::WriteFile(partial, *ruleset) ||
        !base::ReplaceFile(partial, compiled.path, nullptr)) {
      base::DeleteFile(partial);
      return std::nullopt;
    }
  }
  DeleteOtherRulesets(directory, compiled.path);
  return compiled;
}

}  // namespace refrax::content_blocking
