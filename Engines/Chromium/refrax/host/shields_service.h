// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_SHIELDS_SERVICE_H_
#define REFRAX_HOST_SHIELDS_SERVICE_H_

#include <cstdint>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/ref_counted.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/values.h"
#include "refrax/shields/include/shields.h"

class GURL;

namespace refrax {

// One loaded adblock-rust engine, shared by every request that started matching while it was
// current: a policy update swaps the service's reference, and matches in flight keep theirs.
// Queries are thread-safe (the engine is Send + Sync).
class ShieldsEngineRef : public base::RefCountedThreadSafe<ShieldsEngineRef> {
 public:
  ShieldsEngineRef(ShieldsEngine* engine,
                   std::string sha256,
                   std::string resources_sha256,
                   std::vector<std::string> list_ids);
  ShieldsEngineRef(const ShieldsEngineRef&) = delete;
  ShieldsEngineRef& operator=(const ShieldsEngineRef&) = delete;

  const ShieldsEngine* engine() const { return engine_; }
  const std::string& sha256() const { return sha256_; }
  // "" when the policy named no resources.
  const std::string& resources_sha256() const { return resources_sha256_; }

  // The policy's list id for a decision's rule_source_index, or nullopt.
  std::optional<std::string> ListID(int32_t source_index) const;

 private:
  friend class base::RefCountedThreadSafe<ShieldsEngineRef>;
  ~ShieldsEngineRef();

  raw_ptr<ShieldsEngine> engine_;
  const std::string sha256_;
  const std::string resources_sha256_;
  const std::vector<std::string> list_ids_;
};

// Refrax's content-blocking policy (CONTRACT.md §4.5 `contentBlocking`): the adblock-rust
// engine Refrax built and serialized, the hosts it spares, and how strictly it applies. The
// host never parses filter lists; it loads the DAT Refrax names, after checking its format and
// SHA-256, off the UI thread. One per host process, on the UI thread.
class ShieldsService {
 public:
  static ShieldsService& Get();

  ShieldsService(const ShieldsService&) = delete;
  ShieldsService& operator=(const ShieldsService&) = delete;

  // Replaces the policy with the contract's ContentBlockingPolicy. `status` runs once with the
  // contract's `contentBlockingStatus` engine event when the engine is loaded or given up on;
  // pages navigated meanwhile use the previous engine. Returns false for a policy without its
  // required fields.
  bool Apply(const base::DictValue& policy,
             base::OnceCallback<void(std::string event)> status);

  // Replaces the sites where Refrax's site settings turn blocking off (CONTRACT.md §4.5
  // `siteSettings`), lowercase hosts covering their subdomains.
  void SetSiteExceptions(std::set<std::string> hosts);

  // Whether a page whose top frame shows `top_url` is filtered.
  bool IsActiveFor(const GURL& top_url) const;
  // Whether the policy filters such a page once an engine is loaded.
  bool Covers(const GURL& top_url) const;

  // The current engine, or null when there is none or blocking is off.
  scoped_refptr<ShieldsEngineRef> engine() const;

  // Whether blocking is on and the first engine is still loading: nothing filters yet.
  bool IsLoadingFirstEngine() const;
  // Runs `done` once no engine is loading (at once when none is).
  void WhenLoaded(base::OnceClosure done);

 private:
  friend class base::NoDestructor<ShieldsService>;

  ShieldsService();
  ~ShieldsService();

  void OnLoaded(uint64_t generation,
                base::OnceCallback<void(std::string event)> status,
                std::vector<std::string> list_ids,
                std::optional<std::string> failure,
                ShieldsEngine* engine,
                std::string sha256,
                std::string resources_sha256);
  void SetLoading(bool loading);

  bool enabled_ = false;
  std::set<std::string> allowlisted_hosts_;
  std::set<std::string> site_exceptions_;
  scoped_refptr<ShieldsEngineRef> engine_;
  bool loading_ = false;
  std::vector<base::OnceClosure> load_waiters_;
  // Bumped by every Apply, so a slow load can't replace a newer policy's engine.
  uint64_t generation_ = 0;

  base::WeakPtrFactory<ShieldsService> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_SHIELDS_SERVICE_H_
