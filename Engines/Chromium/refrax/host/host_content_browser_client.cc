// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/host_content_browser_client.h"

#include "base/command_line.h"
#include "chrome/browser/chrome_browser_main.h"
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

}  // namespace refrax
