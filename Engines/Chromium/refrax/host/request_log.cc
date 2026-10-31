// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/request_log.h"

#include <utility>

#include "refrax/host/contract_json.h"

namespace refrax {

RequestLog::RequestLog() = default;
RequestLog::~RequestLog() = default;

void RequestLog::Add(base::DictValue entry) {
  entry.Set("seq", static_cast<double>(next_sequence_++));
  if (entries_.size() == kCapacity) {
    entries_.pop_front();
  }
  entries_.push_back(std::move(entry));
}

std::string RequestLog::Since(int64_t since) const {
  base::ListValue entries;
  for (const base::DictValue& entry : entries_) {
    if (entry.FindDouble("seq").value_or(0) > static_cast<double>(since)) {
      entries.Append(entry.Clone());
    }
  }
  return contract::Serialize(
      base::DictValue()
          .Set("entries", std::move(entries))
          .Set("nextSequence", static_cast<double>(next_sequence_)));
}

}  // namespace refrax
