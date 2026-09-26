// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/secrets.h"

#include <string>

#include "base/base64.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace refrax::secrets {
namespace {

std::string AnswerWith(size_t bytes) {
  return R"({"secret":{"value":")" + base::Base64Encode(std::string(bytes, 'k')) + R"("}})";
}

TEST(SecretsTest, RequestNamesTheSecret) {
  EXPECT_EQ(Request(kStorageKey), R"({"secret":{"name":"storageKey"}})");
}

TEST(SecretsTest, AcceptsASecretOfTheContractSize) {
  std::optional<std::vector<uint8_t>> secret = ParseAnswer(AnswerWith(kSecretSize));
  ASSERT_TRUE(secret);
  EXPECT_EQ(secret->size(), kSecretSize);
  EXPECT_EQ((*secret)[0], 'k');
}

TEST(SecretsTest, RejectsEveryOtherAnswer) {
  EXPECT_FALSE(ParseAnswer(R"({"unavailable":{}})"));
  EXPECT_FALSE(ParseAnswer(""));
  EXPECT_FALSE(ParseAnswer("not json"));
  EXPECT_FALSE(ParseAnswer(R"({"secret":{}})"));
  EXPECT_FALSE(ParseAnswer(R"({"secret":{"value":"%%%"}})"));
  // A short secret would make a weaker key; a long one means Refrax and the engine disagree.
  EXPECT_FALSE(ParseAnswer(AnswerWith(16)));
  EXPECT_FALSE(ParseAnswer(AnswerWith(kSecretSize + 1)));
}

}  // namespace
}  // namespace refrax::secrets
