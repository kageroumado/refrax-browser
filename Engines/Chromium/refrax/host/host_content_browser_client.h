// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_HOST_CONTENT_BROWSER_CLIENT_H_
#define REFRAX_HOST_HOST_CONTENT_BROWSER_CLIENT_H_

#include <memory>

#include "chrome/browser/chrome_content_browser_client.h"

namespace refrax {

// Chrome's browser client plus the Refrax engine host's startup parts. The only place Refrax
// enters //chrome's startup (see patches/chrome-host-content-browser-client.patch).
class HostContentBrowserClient : public ChromeContentBrowserClient {
 public:
  HostContentBrowserClient();
  HostContentBrowserClient(const HostContentBrowserClient&) = delete;
  HostContentBrowserClient& operator=(const HostContentBrowserClient&) = delete;
  ~HostContentBrowserClient() override;

  // content::ContentBrowserClient:
  std::unique_ptr<content::BrowserMainParts> CreateBrowserMainParts(
      bool is_integration_test) override;
  void CreateThrottlesForNavigation(
      content::NavigationThrottleRegistry& registry) override;
};

}  // namespace refrax

#endif  // REFRAX_HOST_HOST_CONTENT_BROWSER_CLIENT_H_
