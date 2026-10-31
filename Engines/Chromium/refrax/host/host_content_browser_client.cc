// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/host_content_browser_client.h"

#include <utility>

#include "base/command_line.h"
#include "chrome/browser/chrome_browser_main.h"
#include "content/public/browser/render_frame_host.h"
#include "refrax/host/navigation_policy.h"
#include "net/base/net_errors.h"
#include "net/http/http_request_headers.h"
#include "services/network/public/mojom/web_transport.mojom.h"
#include "services/network/public/mojom/websocket.mojom.h"
#include "refrax/host/refrax_browser_main_extra_parts.h"
#include "refrax/host/shields_document_throttle.h"
#include "refrax/host/shields_url_loader_factory.h"
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
  // Refrax decides before Chrome's throttles see the request, then Shields.
  navigation_policy::MaybeAddThrottle(registry);
  ShieldsDocumentThrottle::MaybeAdd(registry);
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

void HostContentBrowserClient::WillCreateURLLoaderFactory(
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
    bool is_for_network_service) {
  // Chrome's proxies (extensions' webRequest) first, then Shields in front of them: the order
  // Brave uses, so an extension sees what Shields lets through.
  ChromeContentBrowserClient::WillCreateURLLoaderFactory(
      browser_context, frame, render_process_id, type, request_initiator, isolation_info,
      navigation_id, ukm_source_id, factory_builder, header_client, bypass_redirect_checks,
      disable_secure_dns, factory_override, navigation_response_task_runner,
      is_for_network_service);
  ShieldsURLLoaderFactory::Install(browser_context, frame, type, request_initiator,
                                   factory_builder);
}

bool HostContentBrowserClient::WillInterceptWebSocket(content::RenderFrameHost* frame) {
  return ShieldsFiltersConnections(frame) ||
         ChromeContentBrowserClient::WillInterceptWebSocket(frame);
}

void HostContentBrowserClient::CreateWebSocket(
    content::RenderFrameHost* frame,
    WebSocketFactory factory,
    const GURL& url,
    const net::SiteForCookies& site_for_cookies,
    const std::optional<std::string>& user_agent,
    mojo::PendingRemote<network::mojom::WebSocketHandshakeClient> handshake_client,
    WebSocketOptions options) {
  if (!ShieldsFiltersConnections(frame)) {
    ChromeContentBrowserClient::CreateWebSocket(frame, std::move(factory), url,
                                                site_for_cookies, user_agent,
                                                std::move(handshake_client), std::move(options));
    return;
  }
  // A worker's connection has no frame: its site stands in for the page.
  const url::Origin origin = url::Origin::Create(site_for_cookies.RepresentativeUrl());
  const std::optional<content::GlobalRenderFrameHostId> frame_id =
      frame ? std::optional(frame->GetGlobalId()) : std::nullopt;
  ShieldsDecideConnection(
      frame, origin, url, "websocket",
      base::BindOnce(
          [](HostContentBrowserClient* client,
             std::optional<content::GlobalRenderFrameHostId> frame_id, WebSocketFactory factory,
             GURL url, net::SiteForCookies site_for_cookies,
             std::optional<std::string> user_agent,
             mojo::PendingRemote<network::mojom::WebSocketHandshakeClient> handshake_client,
             WebSocketOptions options, bool allowed) {
            content::RenderFrameHost* frame =
                frame_id ? content::RenderFrameHost::FromID(*frame_id) : nullptr;
            // A refused connection is never opened: dropping the handshake client fails the
            // page's WebSocket.
            if (!allowed || (frame_id && !frame)) {
              return;
            }
            if (frame && client->ChromeContentBrowserClient::WillInterceptWebSocket(frame)) {
              client->ChromeContentBrowserClient::CreateWebSocket(
                  frame, std::move(factory), url, site_for_cookies, user_agent,
                  std::move(handshake_client), std::move(options));
              return;
            }
            // What content sends when nothing intercepts: the page's User-Agent, which per-site
            // settings may have changed.
            std::vector<network::mojom::HttpHeaderPtr> headers;
            if (user_agent) {
              headers.push_back(network::mojom::HttpHeader::New(
                  net::HttpRequestHeaders::kUserAgent, *user_agent));
            }
            std::move(factory).Run(url, std::move(headers), std::move(handshake_client),
                                   mojo::NullRemote(), std::move(options.header_client));
          },
          base::Unretained(this), frame_id, std::move(factory), url, site_for_cookies,
          user_agent, std::move(handshake_client), std::move(options)));
}

void HostContentBrowserClient::WillCreateWebTransport(
    int process_id,
    int frame_routing_id,
    const GURL& url,
    const url::Origin& initiator_origin,
    mojo::PendingRemote<network::mojom::WebTransportHandshakeClient> handshake_client,
    WillCreateWebTransportCallback callback) {
  content::RenderFrameHost* frame = content::RenderFrameHost::FromID(process_id, frame_routing_id);
  ShieldsDecideConnection(
      frame, initiator_origin, url, "other",
      base::BindOnce(
          [](HostContentBrowserClient* client, int process_id, int frame_routing_id, GURL url,
             url::Origin initiator_origin,
             mojo::PendingRemote<network::mojom::WebTransportHandshakeClient> handshake_client,
             WillCreateWebTransportCallback callback, bool allowed) {
            if (!allowed) {
              auto error = network::mojom::WebTransportError::New();
              error->net_error = net::ERR_BLOCKED_BY_CLIENT;
              error->details = "Blocked by Refrax Shields";
              std::move(callback).Run(std::move(handshake_client), std::move(error));
              return;
            }
            client->ChromeContentBrowserClient::WillCreateWebTransport(
                process_id, frame_routing_id, url, initiator_origin,
                std::move(handshake_client), std::move(callback));
          },
          base::Unretained(this), process_id, frame_routing_id, url, initiator_origin,
          std::move(handshake_client), std::move(callback)));
}

}  // namespace refrax
