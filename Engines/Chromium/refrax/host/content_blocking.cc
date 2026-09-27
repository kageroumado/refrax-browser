// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/content_blocking.h"

#include <memory>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/path_service.h"
#include "base/strings/string_util.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/browser_process.h"
#include "chrome/common/chrome_paths.h"
#include "components/subresource_filter/content/browser/ruleset_service.h"
#include "components/subresource_filter/content/browser/subresource_filter_observer_manager.h"
#include "components/subresource_filter/content/browser/utils.h"
#include "components/subresource_filter/core/browser/ruleset_version.h"
#include "components/subresource_filter/core/mojom/subresource_filter.mojom.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "refrax/host/content_blocking_compiler.h"
#include "refrax/host/url_matching.h"
#include "url/gurl.h"

namespace refrax {

namespace {

constexpr base::FilePath::CharType kRulesetDirectory[] =
    FILE_PATH_LITERAL("Refrax Content Blocking");

// Activates the subresource filter for a page Refrax filters. Decides at response time, on
// the URL the navigation finally committed to after redirects, the same point Chrome's own
// activation throttle reports at.
class ActivationThrottle : public content::NavigationThrottle {
 public:
  explicit ActivationThrottle(content::NavigationThrottleRegistry& registry)
      : content::NavigationThrottle(registry) {}

  // content::NavigationThrottle:
  ThrottleCheckResult WillProcessResponse() override {
    content::NavigationHandle* navigation = navigation_handle();
    if (!ContentBlocking::Get().IsActiveFor(navigation->GetURL())) {
      return PROCEED;
    }
    auto* observers =
        subresource_filter::SubresourceFilterObserverManager::FromWebContents(
            navigation->GetWebContents());
    if (observers) {
      subresource_filter::mojom::ActivationState state;
      state.activation_level = subresource_filter::mojom::ActivationLevel::kEnabled;
      observers->NotifyPageActivationComputed(navigation, state);
    }
    return PROCEED;
  }

  const char* GetNameForLogging() override {
    return "RefraxContentBlockingActivationThrottle";
  }
};

}  // namespace

// static
ContentBlocking& ContentBlocking::Get() {
  static base::NoDestructor<ContentBlocking> instance;
  return *instance;
}

ContentBlocking::ContentBlocking() = default;
ContentBlocking::~ContentBlocking() = default;

void ContentBlocking::Apply(const base::DictValue& policy) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  received_policy_ = true;
  enabled_ = policy.FindBool("isEnabled").value_or(true);

  allowlisted_hosts_.clear();
  if (const base::ListValue* hosts = policy.FindList("allowlistedHosts")) {
    for (const base::Value& host : *hosts) {
      if (host.is_string()) {
        allowlisted_hosts_.insert(base::ToLowerASCII(host.GetString()));
      }
    }
  }

  std::vector<std::string> lists;
  if (const base::ListValue* policy_lists = policy.FindList("lists")) {
    for (const base::Value& list : *policy_lists) {
      const std::string* contents =
          list.is_dict() ? list.GetDict().FindString("contents") : nullptr;
      if (contents) {
        lists.push_back(*contents);
      }
    }
  }

  base::FilePath user_data;
  base::PathService::Get(chrome::DIR_USER_DATA, &user_data);
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(&content_blocking::Compile, std::move(lists),
                     user_data.Append(kRulesetDirectory)),
      base::BindOnce(
          [](base::WeakPtr<ContentBlocking> self,
             std::optional<content_blocking::CompiledRuleset> compiled) {
            if (!compiled) {
              LOG(ERROR) << "Content blocking: could not write the ruleset";
              return;
            }
            if (self) {
              self->OnCompiled(compiled->content_version, compiled->path);
            }
          },
          weak_factory_.GetWeakPtr()));
}

void ContentBlocking::OnCompiled(const std::string& content_version,
                                 const base::FilePath& ruleset_path) {
  subresource_filter::RulesetService* service =
      g_browser_process->subresource_filter_ruleset_service();
  if (!service) {
    LOG(ERROR) << "Content blocking: the subresource filter is off in this build";
    return;
  }
  subresource_filter::UnindexedRulesetInfo info;
  info.content_version = content_version;
  info.ruleset_path = ruleset_path;
  service->IndexAndStoreAndPublishRulesetIfNeeded(info);
}

void ContentBlocking::SetSiteExceptions(std::set<std::string> hosts) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  site_exceptions_ = std::move(hosts);
}

void ContentBlocking::MaybeAddThrottle(
    content::NavigationThrottleRegistry& registry) const {
  if (!received_policy_ || !enabled_) {
    return;
  }
  content::NavigationHandle& navigation = registry.GetNavigationHandle();
  if (!subresource_filter::IsInSubresourceFilterRoot(&navigation)) {
    return;
  }
  registry.AddThrottle(std::make_unique<ActivationThrottle>(registry));
}

bool ContentBlocking::IsActiveFor(const GURL& url) const {
  if (!received_policy_ || !enabled_ || !url.SchemeIsHTTPOrHTTPS()) {
    return false;
  }
  return !url_matching::IsAllowlistedHost(allowlisted_hosts_, url.host()) &&
         !url_matching::IsAllowlistedHost(site_exceptions_, url.host());
}

}  // namespace refrax
