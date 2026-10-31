// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/request_log.h"

#include <optional>
#include <string>

#include "base/json/json_reader.h"
#include "base/strings/string_number_conversions.h"
#include "base/values.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace refrax {
namespace {

base::DictValue Entry(const std::string& url) {
  return base::DictValue().Set("url", url);
}

base::DictValue Read(const RequestLog& log, int64_t since) {
  std::optional<base::Value> value = base::JSONReader::Read(log.Since(since), base::JSON_PARSE_RFC);
  EXPECT_TRUE(value && value->is_dict());
  return value ? value->GetDict().Clone() : base::DictValue();
}

TEST(RequestLogTest, NumbersEntriesAndReturnsThoseAfterASequence) {
  RequestLog log;
  log.Add(Entry("https://a.test/1"));
  log.Add(Entry("https://a.test/2"));
  log.Add(Entry("https://a.test/3"));

  base::DictValue all = Read(log, 0);
  ASSERT_EQ(all.FindList("entries")->size(), 3u);
  EXPECT_EQ(*all.FindInt("nextSequence"), 4);
  EXPECT_EQ(*(*all.FindList("entries"))[0].GetDict().FindInt("seq"), 1);

  base::DictValue later = Read(log, 2);
  ASSERT_EQ(later.FindList("entries")->size(), 1u);
  EXPECT_EQ(*(*later.FindList("entries"))[0].GetDict().FindString("url"), "https://a.test/3");
}

TEST(RequestLogTest, KeepsTheNewestEntriesAndKeepsCounting) {
  RequestLog log;
  for (size_t i = 0; i < RequestLog::kCapacity + 5; ++i) {
    log.Add(Entry("https://a.test/" + base::NumberToString(i)));
  }
  base::DictValue all = Read(log, 0);
  const base::ListValue& entries = *all.FindList("entries");
  ASSERT_EQ(entries.size(), RequestLog::kCapacity);
  EXPECT_EQ(*entries[0].GetDict().FindInt("seq"), 6);
  EXPECT_EQ(*all.FindInt("nextSequence"), static_cast<int>(RequestLog::kCapacity) + 6);
}

}  // namespace
}  // namespace refrax
