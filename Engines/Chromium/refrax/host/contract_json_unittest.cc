// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/contract_json.h"

#include "testing/gtest/include/gtest/gtest.h"
#include "url/gurl.h"

namespace refrax::contract {
namespace {

TEST(ContractJSONTest, IntegralNumbersHaveNoFraction) {
  // base::Value keeps integers past int32 as doubles; Swift decodes "4294967296.0" into Int
  // only by luck, and byte counts must stay exact.
  EXPECT_EQ(Serialize(base::Value(4294967296.0)), "4294967296");
  EXPECT_EQ(Serialize(base::Value(3.0)), "3");
  EXPECT_EQ(Serialize(base::Value(0.5)), "0.5");
  base::DictValue progress;
  progress.Set("receivedBytes", 8589934592.0);
  EXPECT_EQ(Serialize(progress), R"({"receivedBytes":8589934592})");
}

TEST(ContractJSONTest, MessageWrapsFieldsUnderTheCaseName) {
  EXPECT_EQ(Message("goBack"), R"({"goBack":{}})");
  base::DictValue fields;
  fields.Set("isLoading", true);
  EXPECT_EQ(Message("loadingChanged", std::move(fields)),
            R"({"loadingChanged":{"isLoading":true}})");
}

TEST(ContractJSONTest, ParsesOneCaseWithFields) {
  auto message = ParseMessage(R"({"setZoom":{"factor":1.25}})");
  ASSERT_TRUE(message);
  EXPECT_EQ(message->first, "setZoom");
  EXPECT_EQ(message->second.FindDouble("factor"), 1.25);
}

TEST(ContractJSONTest, RejectsAnythingButOneCase) {
  for (const char* json : {
           "",
           "null",
           "[]",
           "{}",
           R"({"goBack":{},"reload":{}})",
           R"({"goBack":null})",
           R"({"goBack":[]})",
           R"({"goBack":{}} trailing)",
           R"({"goBack":{},})",
       }) {
    EXPECT_FALSE(ParseMessage(json)) << json;
  }
}

TEST(ContractJSONTest, URLValueIsNullForUnusableURLs) {
  EXPECT_TRUE(URLValue(GURL()).is_none());
  EXPECT_TRUE(URLValue(GURL("not a url")).is_none());
  EXPECT_EQ(URLValue(GURL("https://example.com")).GetString(), "https://example.com/");
}

}  // namespace
}  // namespace refrax::contract
