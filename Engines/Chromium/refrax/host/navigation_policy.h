// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_NAVIGATION_POLICY_H_
#define REFRAX_HOST_NAVIGATION_POLICY_H_

#include <string_view>

namespace content {
class NavigationHandle;
class NavigationThrottleRegistry;
}  // namespace content

// Refrax decides where a page's main-frame navigations go (CONTRACT.md §4.3 `navigation`): each
// one waits before its first request until Refrax answers, and goes ahead only on `allow`.
// Refrax answers `cancel` when it takes the URL somewhere itself: a cleaned URL, a preview, a
// new tab.
namespace refrax::navigation_policy {

// Adds the throttle that asks Refrax, when `registry`'s navigation is a main-frame navigation
// of a Refrax page.
void MaybeAddThrottle(content::NavigationThrottleRegistry& registry);

// The contract's NavigationKind for `navigation`.
std::string_view KindName(content::NavigationHandle& navigation);

}  // namespace refrax::navigation_policy

#endif  // REFRAX_HOST_NAVIGATION_POLICY_H_
