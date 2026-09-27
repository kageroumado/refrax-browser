// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/navigation_policy.h"

#include <memory>
#include <optional>
#include <string>

#include "base/containers/fixed_flat_set.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "refrax/host/contract_json.h"
#include "refrax/host/host_page.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace refrax::navigation_policy {

namespace {

// The schemes Refrax decides on: the ones its handlers act on and the contract lets an engine
// report (CONTRACT.md §6). about: navigations, the initial about:blank among them, go ahead.
constexpr auto kAskedSchemes = base::MakeFixedFlatSet<std::string_view>(
    {"http", "https", "file", "data", "blob", "refrax"});

class NavigationPolicyThrottle : public content::NavigationThrottle {
 public:
  NavigationPolicyThrottle(content::NavigationThrottleRegistry& registry,
                           base::WeakPtr<HostPage> page)
      : content::NavigationThrottle(registry), page_(std::move(page)) {}

  // content::NavigationThrottle:
  ThrottleCheckResult WillStartRequest() override {
    content::NavigationHandle* navigation = navigation_handle();
    if (!page_ || !kAskedSchemes.contains(navigation->GetURL().scheme())) {
      return PROCEED;
    }
    base::DictValue fields;
    fields.Set("url", contract::URLValue(navigation->GetURL()));
    fields.Set("kind", KindName(*navigation));
    // A navigation the page started names its document's origin; one Refrax or the user
    // started (address bar, reload, back/forward) names none.
    const std::optional<url::Origin>& initiator = navigation->GetInitiatorOrigin();
    if (navigation->IsRendererInitiated() && initiator) {
      fields.Set("initiatorOrigin", initiator->Serialize());
    }
    page_->SendRequest(contract::Message("navigation", std::move(fields)),
                       base::BindOnce(&NavigationPolicyThrottle::OnAnswer,
                                      weak_factory_.GetWeakPtr()));
    return DEFER;
  }

  const char* GetNameForLogging() override {
    return "RefraxNavigationPolicyThrottle";
  }

 private:
  void OnAnswer(const std::string& answer) {
    auto message = contract::ParseMessage(answer);
    if (message && message->first == "allow") {
      Resume();
    } else {
      CancelDeferredNavigation(CANCEL);
    }
  }

  base::WeakPtr<HostPage> page_;
  base::WeakPtrFactory<NavigationPolicyThrottle> weak_factory_{this};
};

}  // namespace

void MaybeAddThrottle(content::NavigationThrottleRegistry& registry) {
  content::NavigationHandle& navigation = registry.GetNavigationHandle();
  if (!navigation.IsInPrimaryMainFrame()) {
    return;
  }
  HostPage* page = HostPage::FromWebContents(navigation.GetWebContents());
  if (!page) {
    return;
  }
  registry.AddThrottle(
      std::make_unique<NavigationPolicyThrottle>(registry, page->GetWeakPtr()));
}

std::string_view KindName(content::NavigationHandle& navigation) {
  const ui::PageTransition transition = navigation.GetPageTransition();
  if (transition & ui::PAGE_TRANSITION_FORWARD_BACK) {
    return "backForward";
  }
  if (ui::PageTransitionCoreTypeIs(transition, ui::PAGE_TRANSITION_RELOAD)) {
    return "reload";
  }
  if (ui::PageTransitionCoreTypeIs(transition, ui::PAGE_TRANSITION_FORM_SUBMIT)) {
    return "formSubmission";
  }
  // A click on a link in the page. A script's location change also reads LINK, but carries no
  // gesture, or the client-redirect qualifier when it runs during load.
  if (navigation.IsRendererInitiated() && navigation.HasUserGesture() &&
      ui::PageTransitionCoreTypeIs(transition, ui::PAGE_TRANSITION_LINK) &&
      !(transition & ui::PAGE_TRANSITION_CLIENT_REDIRECT)) {
    return "link";
  }
  return "other";
}

}  // namespace refrax::navigation_policy
