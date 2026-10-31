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
  void OpenURL(content::SiteInstance* site_instance,
               const content::OpenURLParams& params,
               base::OnceCallback<void(content::WebContents*)> callback) override;
  void WillCreateURLLoaderFactory(
      content::BrowserContext* browser_context,
      content::RenderFrameHost* frame,
      int render_process_id,
      URLLoaderFactoryType type,
      const url::Origin& request_initiator,
      const net::IsolationInfo& isolation_info,
      std::optional<int64_t> navigation_id,
      ukm::SourceIdObj ukm_source_id,
      network::URLLoaderFactoryBuilder& factory_builder,
      mojo::PendingRemote<network::mojom::TrustedURLLoaderHeaderClient>* header_client,
      bool* bypass_redirect_checks,
      bool* disable_secure_dns,
      network::mojom::URLLoaderFactoryOverridePtr* factory_override,
      scoped_refptr<base::SequencedTaskRunner> navigation_response_task_runner,
      bool is_for_network_service) override;
  bool WillInterceptWebSocket(content::RenderFrameHost* frame) override;
  void CreateWebSocket(content::RenderFrameHost* frame,
                       WebSocketFactory factory,
                       const GURL& url,
                       const net::SiteForCookies& site_for_cookies,
                       const std::optional<std::string>& user_agent,
                       mojo::PendingRemote<network::mojom::WebSocketHandshakeClient>
                           handshake_client,
                       WebSocketOptions options) override;
};

}  // namespace refrax

#endif  // REFRAX_HOST_HOST_CONTENT_BROWSER_CLIENT_H_
