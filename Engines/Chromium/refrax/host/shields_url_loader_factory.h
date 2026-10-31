// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_SHIELDS_URL_LOADER_FACTORY_H_
#define REFRAX_HOST_SHIELDS_URL_LOADER_FACTORY_H_

#include <memory>
#include <optional>
#include <set>

#include "base/containers/unique_ptr_adapters.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/content_browser_client.h"
#include "content/public/browser/global_routing_id.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "services/network/public/mojom/url_loader_factory.mojom.h"
#include "url/origin.h"

namespace content {
class BrowserContext;
}

namespace network {
class URLLoaderFactoryBuilder;
}

namespace refrax {

// Refrax Shields' network half (shields-architecture §4.3): a URLLoaderFactory placed in front of
// every factory a page's documents, workers and navigations load through. Each request of a page
// Shields filters is matched off the UI thread; a blocked one fails with
// ERR_BLOCKED_BY_CLIENT, or is answered with its redirect resource; a $removeparam rewrite is an
// internal redirect; a document's response gets the CSP its $csp rules add. Main-frame blocks
// are ShieldsDocumentThrottle's, which shows the page saying so. Every decision on a Refrax page
// goes to its request log. Owned by its receivers: it deletes itself when the last one and its
// last request are gone. On the UI thread.
class ShieldsURLLoaderFactory : public network::mojom::URLLoaderFactory {
 public:
  // Puts a factory in front of `factory_builder`'s (WillCreateURLLoaderFactory). Downloads go
  // around Shields: the user asked for the file.
  static void Install(content::BrowserContext* browser_context,
                      content::RenderFrameHost* frame,
                      content::ContentBrowserClient::URLLoaderFactoryType type,
                      const url::Origin& request_initiator,
                      network::URLLoaderFactoryBuilder& factory_builder);

  ShieldsURLLoaderFactory(const ShieldsURLLoaderFactory&) = delete;
  ShieldsURLLoaderFactory& operator=(const ShieldsURLLoaderFactory&) = delete;
  ~ShieldsURLLoaderFactory() override;

  // network::mojom::URLLoaderFactory:
  void CreateLoaderAndStart(
      mojo::PendingReceiver<network::mojom::URLLoader> loader,
      int32_t request_id,
      uint32_t options,
      const network::ResourceRequest& request,
      mojo::PendingRemote<network::mojom::URLLoaderClient> client,
      const net::MutableNetworkTrafficAnnotationTag& traffic_annotation) override;
  void Clone(mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver) override;

 private:
  class InProgressRequest;

  ShieldsURLLoaderFactory(const content::BrowserContext* browser_context,
                          std::optional<content::GlobalRenderFrameHostId> frame,
                          bool is_navigation,
                          const url::Origin& request_initiator,
                          mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
                          mojo::PendingRemote<network::mojom::URLLoaderFactory> target);

  // The URL of the page the request belongs to (its outermost main frame), for deciding
  // whether Shields filters it.
  GURL TopFrameURL(const network::ResourceRequest& request) const;
  // The URL of the frame the factory belongs to, for the log.
  GURL FrameURL() const;
  // Appends `entry` to the request log of the frame's Refrax page, or for a worker's request, of
  // a page of the worker's origin.
  void Log(base::DictValue entry) const;

  void RemoveRequest(InProgressRequest* request);
  void MaybeDestroy();

  // Compared, never used: which profile a worker's request belongs to.
  const raw_ptr<const content::BrowserContext> browser_context_;
  const std::optional<content::GlobalRenderFrameHostId> frame_;
  // Whether the factory loads navigations, whose blocked documents ShieldsDocumentThrottle
  // answers.
  const bool is_navigation_;
  const url::Origin request_initiator_;
  mojo::ReceiverSet<network::mojom::URLLoaderFactory> receivers_;
  mojo::Remote<network::mojom::URLLoaderFactory> target_;
  std::set<std::unique_ptr<InProgressRequest>, base::UniquePtrComparator> requests_;

  base::WeakPtrFactory<ShieldsURLLoaderFactory> weak_factory_{this};
};

// WebSockets and WebTransport: a connection Shields blocks is never opened.
// Whether Shields may filter connections of `frame`, or with no frame (a shared or service
// worker), any connection.
bool ShieldsFiltersConnections(content::RenderFrameHost* frame);
// Decides a connection to `url` of adblock-rust's `type`, from `frame`, or with no frame from
// a worker of `origin`; `done` runs on the UI thread with whether it may open.
void ShieldsDecideConnection(content::RenderFrameHost* frame,
                             const url::Origin& origin,
                             const GURL& url,
                             std::string_view type,
                             base::OnceCallback<void(bool allowed)> done);

}  // namespace refrax

#endif  // REFRAX_HOST_SHIELDS_URL_LOADER_FACTORY_H_
