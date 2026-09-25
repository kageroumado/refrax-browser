// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/url_matching.h"

#include "testing/gtest/include/gtest/gtest.h"

namespace refrax::url_matching {
namespace {

TEST(IsAllowlistedHostTest, MatchesTheHostAndItsSubdomains) {
  std::set<std::string> allowlisted = {"example.com"};
  EXPECT_TRUE(IsAllowlistedHost(allowlisted, "example.com"));
  EXPECT_TRUE(IsAllowlistedHost(allowlisted, "www.example.com"));
  EXPECT_TRUE(IsAllowlistedHost(allowlisted, "a.b.example.com"));
  EXPECT_TRUE(IsAllowlistedHost(allowlisted, "WWW.Example.COM"));
}

TEST(IsAllowlistedHostTest, NeverMatchesALookalikeOrAParent) {
  std::set<std::string> allowlisted = {"example.com"};
  EXPECT_FALSE(IsAllowlistedHost(allowlisted, "notexample.com"));
  EXPECT_FALSE(IsAllowlistedHost(allowlisted, "example.com.evil.test"));
  EXPECT_FALSE(IsAllowlistedHost(allowlisted, "com"));
  EXPECT_FALSE(IsAllowlistedHost(allowlisted, ""));
  EXPECT_FALSE(IsAllowlistedHost({"sub.example.com"}, "example.com"));
  EXPECT_FALSE(IsAllowlistedHost({}, "example.com"));
}

TEST(IsAllowlistedHostTest, MatchesAddressesExactly) {
  EXPECT_TRUE(IsAllowlistedHost({"127.0.0.1"}, "127.0.0.1"));
  EXPECT_FALSE(IsAllowlistedHost({"0.1"}, "127.0.0.1"));
  EXPECT_FALSE(IsAllowlistedHost({"0.0.1"}, "127.0.0.1"));
  EXPECT_TRUE(IsAllowlistedHost({"[::1]"}, "[::1]"));
}

TEST(MatchPatternToRegexTest, BuildsAnchoredExpressions) {
  EXPECT_EQ(MatchPatternToRegex("https://example.com/*"),
            "/^https:\\/\\/example\\.com(?::\\d+)?\\/.*$/");
  EXPECT_EQ(MatchPatternToRegex("*://*.example.com/a?b*"),
            "/^https?:\\/\\/(?:[^/:]+\\.)?example\\.com(?::\\d+)?\\/a\\?b.*$/");
  EXPECT_EQ(MatchPatternToRegex("http://localhost:8080/"),
            "/^http:\\/\\/localhost:8080\\/$/");
  EXPECT_EQ(MatchPatternToRegex("file:///Users/*"), "/^file:\\/\\/\\/Users\\/.*$/");
  EXPECT_EQ(MatchPatternToRegex("*://*/*"), "/^https?:\\/\\/[^/:]+(?::\\d+)?\\/.*$/");
}

TEST(MatchPatternToRegexTest, LowercasesTheHost) {
  EXPECT_EQ(MatchPatternToRegex("https://Example.COM/"),
            MatchPatternToRegex("https://example.com/"));
}

TEST(MatchPatternToRegexTest, RejectsMalformedPatterns) {
  for (const char* pattern : {
           "",
           "example.com",
           "https://example.com",
           "https:/example.com/",
           "://example.com/",
           "HTTPS://example.com/",
           "ht*p://example.com/",
           "https://*example.com/",
           "https://exa*mple.com/",
           "https://*./",
           "https:///path",
           "file://host/path",
           "https://example.com:/",
           "https://example.com:8x/",
       }) {
    EXPECT_FALSE(MatchPatternToRegex(pattern)) << pattern;
  }
}

TEST(MatchPatternToRegexTest, EscapesRegexSyntaxInPaths) {
  EXPECT_EQ(MatchPatternToRegex("https://a.example/(x)[y]{z}|$^+.\\/"),
            "/^https:\\/\\/a\\.example(?::\\d+)?\\/\\(x\\)\\[y\\]\\{z\\}\\|\\$\\^\\+\\.\\\\\\/$/");
}

TEST(ScriptGuardTest, EmbedsEachPatternOnce) {
  std::string guard = ScriptGuard({"https://a.example/*"}, {"https://a.example/private*"});
  EXPECT_NE(guard.find(*MatchPatternToRegex("https://a.example/*")), std::string::npos);
  EXPECT_NE(guard.find(*MatchPatternToRegex("https://a.example/private*")),
            std::string::npos);
}

TEST(ScriptGuardTest, AMalformedMatchAdmitsNothingAndAMalformedExcludeRemovesNothing) {
  std::string only_malformed = ScriptGuard({"not a pattern"}, {});
  EXPECT_NE(only_malformed.find("var matches = [/(?!)/]"), std::string::npos);
  std::string malformed_exclude = ScriptGuard({}, {"not a pattern"});
  EXPECT_NE(malformed_exclude.find("var excludes = []"), std::string::npos);
}

}  // namespace
}  // namespace refrax::url_matching
