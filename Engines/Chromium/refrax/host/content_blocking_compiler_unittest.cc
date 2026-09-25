// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/content_blocking_compiler.h"

#include <string>
#include <vector>

#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "components/subresource_filter/core/common/unindexed_ruleset.h"
#include "components/url_pattern_index/proto/rules.pb.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "third_party/protobuf/src/google/protobuf/io/zero_copy_stream_impl_lite.h"

namespace refrax::content_blocking {
namespace {

using url_pattern_index::proto::UrlRule;

// The URL rules of the ruleset at `path`, in order.
std::vector<UrlRule> ReadRules(const base::FilePath& path) {
  std::string contents;
  EXPECT_TRUE(base::ReadFileToString(path, &contents));
  google::protobuf::io::ArrayInputStream input(contents.data(),
                                               static_cast<int>(contents.size()));
  subresource_filter::UnindexedRulesetReader reader(&input);
  std::vector<UrlRule> rules;
  url_pattern_index::proto::FilteringRules chunk;
  while (reader.ReadNextChunk(&chunk)) {
    rules.insert(rules.end(), chunk.url_rules().begin(), chunk.url_rules().end());
  }
  return rules;
}

std::vector<UrlRule> CompileRules(const std::vector<std::string>& lists) {
  base::ScopedTempDir directory;
  EXPECT_TRUE(directory.CreateUniqueTempDir());
  std::optional<CompiledRuleset> compiled = Compile(lists, directory.GetPath());
  EXPECT_TRUE(compiled);
  return compiled ? ReadRules(compiled->path) : std::vector<UrlRule>();
}

std::vector<base::FilePath> Files(const base::FilePath& directory) {
  std::vector<base::FilePath> files;
  base::FileEnumerator enumerator(directory, false, base::FileEnumerator::FILES);
  for (base::FilePath file = enumerator.Next(); !file.empty(); file = enumerator.Next()) {
    files.push_back(file);
  }
  return files;
}

TEST(NormalizeRuleTest, SpellsOutUBlockAliases) {
  EXPECT_EQ(NormalizeRule("||ads.example^$3p,xhr"),
            "||ads.example^$third-party,xmlhttprequest");
  EXPECT_EQ(NormalizeRule("||a.example^$css,img,frame,doc,beacon"),
            "||a.example^$stylesheet,image,subdocument,document,ping");
  EXPECT_EQ(NormalizeRule("@@||a.example^$ghide,ehide"),
            "@@||a.example^$generichide,elemhide");
}

TEST(NormalizeRuleTest, PartyAliasesKeepTheirPolarityUnderNegation) {
  EXPECT_EQ(NormalizeRule("/x.js$1p"), "/x.js$~third-party");
  EXPECT_EQ(NormalizeRule("/x.js$first-party"), "/x.js$~third-party");
  EXPECT_EQ(NormalizeRule("/x.js$~1p"), "/x.js$third-party");
  EXPECT_EQ(NormalizeRule("/x.js$~3p"), "/x.js$~third-party");
}

TEST(NormalizeRuleTest, RenamesFromToDomainKeepingItsValue) {
  EXPECT_EQ(NormalizeRule("/ad.png$from=a.example|~b.example"),
            "/ad.png$domain=a.example|~b.example");
}

TEST(NormalizeRuleTest, LeavesEverythingElseAlone) {
  for (const char* line : {
           "! Title: EasyList",
           "[Adblock Plus 2.0]",
           "example.com##.ad",
           "example.com#@#.ad",
           "example.com##+js(set, x, 1)",
           "||plain.example^",
           "/ads/*",
           "||a.example^$script,domain=b.example",
           "||a.example^$removeparam=utm",
       }) {
    EXPECT_EQ(NormalizeRule(line), line) << line;
  }
}

TEST(NormalizeRuleTest, OptionsFollowTheLastDollar) {
  // A `$` inside the pattern is part of it; only the last one starts the options.
  EXPECT_EQ(NormalizeRule("/a$b/$xhr"), "/a$b/$xmlhttprequest");
}

TEST(CompileTest, KeepsNetworkRulesAndDropsWhatTheFilterCannotEnforce) {
  std::vector<UrlRule> rules = CompileRules({
      "! comment\n"
      "||blocked.example^\n"
      "@@||allowed.example^\n"
      "example.com##.cosmetic\n"
      "/^https?:\\/\\/regex\\.example/\n"
      "||param.example^$removeparam=x\n"
      "||redirect.example^$redirect=noop.js\n"
      "||important.example^$important\n"
      "||csp.example^$csp=script-src 'none'\n"});
  ASSERT_EQ(rules.size(), 2u);
  EXPECT_EQ(rules[0].url_pattern(), "blocked.example^");
  EXPECT_EQ(rules[0].semantics(), url_pattern_index::proto::RULE_SEMANTICS_BLOCKLIST);
  EXPECT_EQ(rules[1].url_pattern(), "allowed.example^");
  EXPECT_EQ(rules[1].semantics(), url_pattern_index::proto::RULE_SEMANTICS_ALLOWLIST);
}

TEST(CompileTest, AliasedRulesSurviveCompiling) {
  std::vector<UrlRule> rules = CompileRules({"/tracker.js$1p,script"});
  ASSERT_EQ(rules.size(), 1u);
  EXPECT_EQ(rules[0].source_type(), url_pattern_index::proto::SOURCE_TYPE_FIRST_PARTY);
  EXPECT_EQ(rules[0].element_types(), url_pattern_index::proto::ELEMENT_TYPE_SCRIPT);
}

TEST(CompileTest, XhrAndPingRulesAlsoCoverOther) {
  // The filter files fetch(), XMLHttpRequest and sendBeacon as ELEMENT_TYPE_OTHER.
  std::vector<UrlRule> rules =
      CompileRules({"/api$xhr\n/beacon$ping\n/pic.png$image"});
  ASSERT_EQ(rules.size(), 3u);
  EXPECT_TRUE(rules[0].element_types() & url_pattern_index::proto::ELEMENT_TYPE_OTHER);
  EXPECT_TRUE(rules[0].element_types() &
              url_pattern_index::proto::ELEMENT_TYPE_XMLHTTPREQUEST);
  EXPECT_TRUE(rules[1].element_types() & url_pattern_index::proto::ELEMENT_TYPE_OTHER);
  EXPECT_EQ(rules[2].element_types(), url_pattern_index::proto::ELEMENT_TYPE_IMAGE);
}

TEST(CompileTest, ReadsEveryLineEnding) {
  EXPECT_EQ(CompileRules({"||a.example^\r\n||b.example^\r||c.example^\n"}).size(), 3u);
}

TEST(CompileTest, EmptyListsCompileToAnEmptyRuleset) {
  EXPECT_TRUE(CompileRules({}).empty());
  EXPECT_TRUE(CompileRules({"", "! only a comment"}).empty());
}

TEST(CompileTest, SameListsReuseTheirRulesetFile) {
  base::ScopedTempDir directory;
  ASSERT_TRUE(directory.CreateUniqueTempDir());
  auto first = Compile({"||a.example^"}, directory.GetPath());
  ASSERT_TRUE(first);
  // A reused file is left untouched: mark it and see the mark survive.
  ASSERT_TRUE(base::AppendToFile(first->path, "!"));
  auto second = Compile({"||a.example^"}, directory.GetPath());
  ASSERT_TRUE(second);
  EXPECT_EQ(second->content_version, first->content_version);
  EXPECT_EQ(second->path, first->path);
  std::string contents;
  ASSERT_TRUE(base::ReadFileToString(second->path, &contents));
  EXPECT_TRUE(contents.ends_with("!"));
}

TEST(CompileTest, NewListsReplaceTheOldRuleset) {
  base::ScopedTempDir directory;
  ASSERT_TRUE(directory.CreateUniqueTempDir());
  auto first = Compile({"||a.example^"}, directory.GetPath());
  auto second = Compile({"||b.example^"}, directory.GetPath());
  ASSERT_TRUE(first && second);
  EXPECT_NE(first->content_version, second->content_version);
  EXPECT_EQ(Files(directory.GetPath()), std::vector<base::FilePath>{second->path});
}

TEST(CompileTest, VersionSeparatesListBoundaries) {
  base::ScopedTempDir directory;
  ASSERT_TRUE(directory.CreateUniqueTempDir());
  auto joined = Compile({"||a.example^\n||b.example^"}, directory.GetPath());
  auto split = Compile({"||a.example^\n", "||b.example^"}, directory.GetPath());
  auto reordered = Compile({"||b.example^", "||a.example^\n"}, directory.GetPath());
  ASSERT_TRUE(joined && split && reordered);
  EXPECT_NE(joined->content_version, split->content_version);
  EXPECT_NE(split->content_version, reordered->content_version);
}

TEST(CompileTest, VersionNamesTheFormat) {
  base::ScopedTempDir directory;
  ASSERT_TRUE(directory.CreateUniqueTempDir());
  auto compiled = Compile({"||a.example^"}, directory.GetPath());
  ASSERT_TRUE(compiled);
  EXPECT_TRUE(compiled->content_version.starts_with("refrax"));
  EXPECT_EQ(compiled->path.BaseName().value(), compiled->content_version + ".pb");
}

TEST(CompileTest, FailsWhenTheDirectoryCannotBeCreated) {
  base::ScopedTempDir directory;
  ASSERT_TRUE(directory.CreateUniqueTempDir());
  base::FilePath file = directory.GetPath().AppendASCII("file");
  ASSERT_TRUE(base::WriteFile(file, "x"));
  EXPECT_FALSE(Compile({"||a.example^"}, file.AppendASCII("rules")));
}

}  // namespace
}  // namespace refrax::content_blocking
