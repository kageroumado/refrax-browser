// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_CONTENT_BLOCKING_COMPILER_H_
#define REFRAX_HOST_CONTENT_BLOCKING_COMPILER_H_

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "base/files/file_path.h"

// Filter lists (Adblock Plus / uBlock syntax) → the subresource filter's unindexed ruleset.
// Blocking I/O: runs on a MayBlock sequence.
namespace refrax::content_blocking {

struct CompiledRuleset {
  // Identifies the lists' contents and this compiler's output format; the RulesetService
  // skips indexing a version it already holds.
  std::string content_version;
  base::FilePath path;
};

// `line` rewritten into the dialect Chromium's RuleParser reads: uBlock's option aliases
// (`3p`, `xhr`, `frame`, …) spelled out. Lines the parser rejects stay as they are and are
// dropped by it.
std::string NormalizeRule(std::string_view line);

// Writes the network rules of `lists` into `directory`, removing rulesets of other versions,
// and returns where the new one is. Reuses an existing file for the same contents. Returns
// nullopt when the directory can't be written.
std::optional<CompiledRuleset> Compile(const std::vector<std::string>& lists,
                                       const base::FilePath& directory);

}  // namespace refrax::content_blocking

#endif  // REFRAX_HOST_CONTENT_BLOCKING_COMPILER_H_
