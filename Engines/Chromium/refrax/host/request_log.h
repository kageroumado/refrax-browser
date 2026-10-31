// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_REQUEST_LOG_H_
#define REFRAX_HOST_REQUEST_LOG_H_

#include <cstdint>
#include <string>

#include "base/containers/circular_deque.h"
#include "base/values.h"

namespace refrax {

// A page's content-blocking decisions, newest last, for Refrax to pull (CONTRACT.md §4.7). Keeps
// the newest kCapacity entries within kMaxBytes of JSON; sequence numbers keep counting across the
// ones dropped. One answer carries at most kMaxReplyBytes; the rest comes with the next pull.
class RequestLog {
 public:
  static constexpr size_t kCapacity = 2000;
  static constexpr size_t kMaxBytes = 2 * 1024 * 1024;
  static constexpr size_t kMaxReplyBytes = 3 * 1024 * 1024;

  RequestLog();
  RequestLog(const RequestLog&) = delete;
  RequestLog& operator=(const RequestLog&) = delete;
  ~RequestLog();

  // Numbers `entry` (its `seq`) and appends it.
  void Add(base::DictValue entry);

  // {"entries": [entries with seq > since, oldest first], "nextSequence": the seq to ask after
  // next time}: the last entry's, or `since` when there are none.
  std::string Since(int64_t since) const;

 private:
  struct Entry {
    int64_t seq;
    std::string json;
  };

  base::circular_deque<Entry> entries_;
  size_t bytes_ = 0;
  int64_t next_sequence_ = 1;
};

}  // namespace refrax

#endif  // REFRAX_HOST_REQUEST_LOG_H_
