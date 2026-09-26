// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/host_content_browser_client.h"

#include "base/command_line.h"
#include "chrome/browser/chrome_browser_main.h"
#include "refrax/host/content_blocking.h"
#include "refrax/host/refrax_browser_main_extra_parts.h"
#include "refrax/host/switches.h"

namespace refrax {

HostContentBrowserClient::HostContentBrowserClient() = default;
HostContentBrowserClient::~HostContentBrowserClient() = default;

std::unique_ptr<content::BrowserMainParts>
HostContentBrowserClient::CreateBrowserMainParts(bool is_integration_test) {
  std::unique_ptr<content::BrowserMainParts> parts =
      ChromeContentBrowserClient::CreateBrowserMainParts(is_integration_test);
  if (base::CommandLine::ForCurrentProcess()->HasSwitch(
          switches::kRefraxBootstrap)) {
    static_cast<ChromeBrowserMainParts*>(parts.get())
        ->AddParts(std::make_unique<RefraxBrowserMainExtraParts>());
  }
  return parts;
}

void HostContentBrowserClient::CreateThrottlesForNavigation(
    content::NavigationThrottleRegistry& registry) {
  // First, so the filter's page activation is known before Chrome's subresource filter
  // throttles act on it.
  ContentBlocking::Get().MaybeAddThrottle(registry);
  ChromeContentBrowserClient::CreateThrottlesForNavigation(registry);
}

void HostContentBrowserClient::OpenURL(
    content::SiteInstance* site_instance,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::WebContents*)> callback) {
  // Chrome would open a browser window of its own; Refrax owns every window. A service
  // worker's clients.openWindow() resolves with null, and Refrax shows the site itself when
  // the worker's notification is clicked.
  std::move(callback).Run(nullptr);
}

}  // namespace refrax
