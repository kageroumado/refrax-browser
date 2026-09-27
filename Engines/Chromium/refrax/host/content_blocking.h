// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_CONTENT_BLOCKING_H_
#define REFRAX_HOST_CONTENT_BLOCKING_H_

#include <set>
#include <string>

#include "base/files/file_path.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/values.h"

class GURL;

namespace content {
class NavigationThrottleRegistry;
}

namespace refrax {

// Refrax's content-blocking policy, enforced through Chromium's subresource filter: the
// filter lists compile into the filter's ruleset (replacing Google's ad list, which this
// build never downloads), and every page Refrax has not allowlisted activates it. One per
// host process, on the UI thread.
//
// Network rules only. Cosmetic (`##`) rules and scriptlets have no place in the subresource
// filter and are left out.
class ContentBlocking {
 public:
  static ContentBlocking& Get();

  ContentBlocking(const ContentBlocking&) = delete;
  ContentBlocking& operator=(const ContentBlocking&) = delete;

  // Replaces the policy with the contract's ContentBlockingPolicy. Compiling the lists happens
  // off the UI thread; pages navigated meanwhile use the previous ruleset.
  void Apply(const base::DictValue& policy);

  // Adds the throttle that activates the filter for `registry`'s navigation, if it needs one.
  // Must run before Chrome adds its subresource filter throttles.
  void MaybeAddThrottle(content::NavigationThrottleRegistry& registry) const;

  // Replaces the sites where Refrax's site settings turn blocking off (CONTRACT.md §4.5
  // `siteSettings`), lowercase hosts covering their subdomains.
  void SetSiteExceptions(std::set<std::string> hosts);

  // Whether a page at `url` is filtered.
  bool IsActiveFor(const GURL& url) const;

 private:
  friend class base::NoDestructor<ContentBlocking>;

  ContentBlocking();
  ~ContentBlocking();

  void OnCompiled(const std::string& content_version,
                  const base::FilePath& ruleset_path);

  bool received_policy_ = false;
  bool enabled_ = false;
  std::set<std::string> allowlisted_hosts_;
  std::set<std::string> site_exceptions_;

  base::WeakPtrFactory<ContentBlocking> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_CONTENT_BLOCKING_H_
