// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/request_log.h"

#include <utility>

#include "base/strings/string_number_conversions.h"
#include "refrax/host/contract_json.h"

namespace refrax {

RequestLog::RequestLog() = default;
RequestLog::~RequestLog() = default;

void RequestLog::Add(base::DictValue entry) {
  const int64_t seq = next_sequence_++;
  entry.Set("seq", static_cast<double>(seq));
  std::string json = contract::Serialize(entry);
  bytes_ += json.size();
  entries_.push_back({seq, std::move(json)});
  while (entries_.size() > kCapacity || (bytes_ > kMaxBytes && entries_.size() > 1)) {
    bytes_ -= entries_.front().json.size();
    entries_.pop_front();
  }
}

std::string RequestLog::Since(int64_t since) const {
  std::string entries;
  int64_t last = since;
  for (const Entry& entry : entries_) {
    if (entry.seq <= since) {
      continue;
    }
    if (!entries.empty() && entries.size() + entry.json.size() > kMaxReplyBytes) {
      break;
    }
    if (!entries.empty()) {
      entries += ',';
    }
    entries += entry.json;
    last = entry.seq;
  }
  return "{\"entries\":[" + entries + "],\"nextSequence\":" + base::NumberToString(last) + "}";
}

}  // namespace refrax
