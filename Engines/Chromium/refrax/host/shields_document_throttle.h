// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_SHIELDS_DOCUMENT_THROTTLE_H_
#define REFRAX_HOST_SHIELDS_DOCUMENT_THROTTLE_H_

#include "base/memory/weak_ptr.h"
#include "content/public/browser/navigation_throttle.h"
#include "refrax/host/shields_matching.h"

namespace content {
class NavigationThrottleRegistry;
}

namespace refrax {

// Blocks a page a $document rule names before its request leaves (shields-architecture C3):
// the navigation fails with ERR_BLOCKED_BY_CLIENT and the frame shows a page saying Shields
// blocked it and by which rule. Decides at the start and at each redirect, off the UI thread.
class ShieldsDocumentThrottle : public content::NavigationThrottle {
 public:
  // Adds the throttle to `registry`'s navigation when it is an outermost main-frame one.
  static void MaybeAdd(content::NavigationThrottleRegistry& registry);

  explicit ShieldsDocumentThrottle(content::NavigationThrottleRegistry& registry);
  ShieldsDocumentThrottle(const ShieldsDocumentThrottle&) = delete;
  ShieldsDocumentThrottle& operator=(const ShieldsDocumentThrottle&) = delete;
  ~ShieldsDocumentThrottle() override;

  // content::NavigationThrottle:
  ThrottleCheckResult WillStartRequest() override;
  ThrottleCheckResult WillRedirectRequest() override;
  const char* GetNameForLogging() override;

 private:
  ThrottleCheckResult Decide();
  void OnDecided(shields::Request request, shields::Decision decision);

  base::WeakPtrFactory<ShieldsDocumentThrottle> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_SHIELDS_DOCUMENT_THROTTLE_H_
