// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_REQUEST_LOG_H_
#define REFRAX_HOST_REQUEST_LOG_H_

#include <cstdint>
#include <string>

#include "base/containers/circular_deque.h"
#include "base/values.h"

namespace refrax {

// A page's content-blocking decisions, newest last, for Refrax to pull (CONTRACT.md §4.7). Keeps
// the newest kCapacity entries; sequence numbers keep counting across the ones dropped.
class RequestLog {
 public:
  static constexpr size_t kCapacity = 2000;

  RequestLog();
  RequestLog(const RequestLog&) = delete;
  RequestLog& operator=(const RequestLog&) = delete;
  ~RequestLog();

  // Numbers `entry` (its `seq`) and appends it.
  void Add(base::DictValue entry);

  // {"entries": [entries with seq > since, oldest first], "nextSequence": the next seq}.
  std::string Since(int64_t since) const;

 private:
  base::circular_deque<base::DictValue> entries_;
  int64_t next_sequence_ = 1;
};

}  // namespace refrax

#endif  // REFRAX_HOST_REQUEST_LOG_H_
