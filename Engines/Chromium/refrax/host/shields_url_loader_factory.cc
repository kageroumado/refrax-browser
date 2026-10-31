// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/shields_url_loader_factory.h"

#include <algorithm>
#include <utility>

#include "base/functional/bind.h"
#include "base/byte_size.h"
#include "base/strings/stringprintf.h"
#include "content/public/browser/render_frame_host.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/system/data_pipe.h"
#include "net/base/data_url.h"
#include "net/base/net_errors.h"
#include "net/http/http_response_headers.h"
#include "net/http/http_status_code.h"
#include "net/http/http_util.h"
#include "net/url_request/redirect_info.h"
#include "refrax/host/page_shields.h"
#include "refrax/host/shields_matching.h"
#include "refrax/host/shields_service.h"
#include "services/network/public/cpp/content_security_policy/content_security_policy.h"
#include "services/network/public/cpp/parsed_headers.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/url_loader_completion_status.h"
#include "services/network/public/cpp/url_loader_factory_builder.h"
#include "services/network/public/mojom/early_hints.mojom.h"
#include "services/network/public/mojom/url_loader.mojom.h"
#include "services/network/public/mojom/url_response_head.mojom.h"

namespace refrax {

namespace {

// Redirects (the network's and Shields' own) a request may go through before it fails.
constexpr int kMaxRedirects = 20;

content::RenderFrameHost* FrameFor(const std::optional<content::GlobalRenderFrameHostId>& id) {
  return id ? content::RenderFrameHost::FromID(*id) : nullptr;
}

}  // namespace

// One request through the factory: a URLLoader to the requester and a URLLoaderClient of the
// real loader, forwarding between them and stepping in where Shields decides.
class ShieldsURLLoaderFactory::InProgressRequest : public network::mojom::URLLoader,
                                                   public network::mojom::URLLoaderClient {
 public:
  InProgressRequest(ShieldsURLLoaderFactory* factory,
                    mojo::PendingReceiver<network::mojom::URLLoader> loader,
                    int32_t request_id,
                    uint32_t options,
                    const network::ResourceRequest& request,
                    mojo::PendingRemote<network::mojom::URLLoaderClient> client,
                    const net::MutableNetworkTrafficAnnotationTag& traffic_annotation,
                    scoped_refptr<ShieldsEngineRef> engine)
      : factory_(factory),
        loader_receiver_(this, std::move(loader)),
        request_id_(request_id),
        options_(options),
        request_(request),
        client_(std::move(client)),
        traffic_annotation_(traffic_annotation),
        engine_(std::move(engine)) {
    loader_receiver_.set_disconnect_handler(
        base::BindOnce(&InProgressRequest::Finish, base::Unretained(this)));
    client_.set_disconnect_handler(
        base::BindOnce(&InProgressRequest::Finish, base::Unretained(this)));
    shields_request_.type =
        shields::RequestType(request.destination, request.is_outermost_main_frame,
                             request.keepalive);
    shields_request_.method = request.method;
    shields_request_.frame_url = factory_->FrameURL();
    if (shields_request_.type == "main_frame") {
      shields_request_.frame_url = request.url;
    }
  }

  void Start() { Decide(); }

  // network::mojom::URLLoader:
  void FollowRedirect(network::HttpRequestHeadersUpdateParams headers_update_params,
                      const std::optional<GURL>& new_url) override {
    if (pending_shields_redirect_.is_valid()) {
      // Shields' own redirect: the request starts over at the rewritten URL.
      request_.url = new_url.value_or(pending_shields_redirect_);
      pending_shields_redirect_ = GURL();
      headers_update_params.Apply(request_.headers, request_.cors_exempt_headers);
      Decide();
      return;
    }
    if (pending_network_redirect_.is_valid()) {
      request_.url = new_url.value_or(pending_network_redirect_);
      pending_network_redirect_ = GURL();
      Retarget();
      if (target_loader_.is_bound()) {
        // A rewrite of the redirect's target ($removeparam) is sent along as the URL to load.
        std::optional<GURL> follow = new_url;
        if (!follow && request_.url != redirect_target_) {
          follow = request_.url;
        }
        target_loader_->FollowRedirect(std::move(headers_update_params), follow);
      }
    }
  }

  void SetPriority(net::RequestPriority priority, int32_t intra_priority_value) override {
    if (target_loader_.is_bound()) {
      target_loader_->SetPriority(priority, intra_priority_value);
    }
  }

  // network::mojom::URLLoaderClient:
  void OnReceiveEarlyHints(network::mojom::EarlyHintsPtr early_hints) override {
    client_->OnReceiveEarlyHints(std::move(early_hints));
  }

  void OnReceiveResponse(network::mojom::URLResponseHeadPtr head,
                         mojo::ScopedDataPipeConsumerHandle body,
                         std::optional<mojo_base::BigBuffer> cached_metadata) override {
    if (engine_ && head->headers &&
        (shields_request_.type == "main_frame" || shields_request_.type == "sub_frame")) {
      AddContentSecurityPolicy(*head);
    }
    client_->OnReceiveResponse(std::move(head), std::move(body), std::move(cached_metadata));
  }

  void OnReceiveRedirect(const net::RedirectInfo& redirect_info,
                         network::mojom::URLResponseHeadPtr head) override {
    if (++redirects_ > kMaxRedirects) {
      Fail(net::ERR_TOO_MANY_REDIRECTS);
      return;
    }
    redirect_target_ = redirect_info.new_url;
    // A page redirected to a site Shields spares is not filtered.
    if (!engine_ || (shields_request_.type == "main_frame" &&
                     !ShieldsService::Get().IsActiveFor(redirect_info.new_url))) {
      pending_network_redirect_ = redirect_info.new_url;
      client_->OnReceiveRedirect(redirect_info, std::move(head));
      return;
    }
    // The new location is a request of its own: it is decided before the requester follows.
    target_client_receiver_.Pause();
    shields::Request next = shields_request_;
    next.url = redirect_info.new_url;
    shields::MatchOnPool(
        engine_, std::move(next),
        base::BindOnce(&InProgressRequest::OnRedirectDecided, weak_factory_.GetWeakPtr(),
                       redirect_info, std::move(head)));
  }

  void OnUploadProgress(int64_t current_position,
                        int64_t total_size,
                        OnUploadProgressCallback callback) override {
    client_->OnUploadProgress(current_position, total_size, std::move(callback));
  }

  void OnTransferSizeUpdated(int32_t transfer_size_diff) override {
    client_->OnTransferSizeUpdated(transfer_size_diff);
  }

  void OnComplete(const network::URLLoaderCompletionStatus& status) override {
    client_->OnComplete(status);
    Finish();
  }

 private:
  // Points shields_request_ at request_.url: the URL decided and logged, and for a page's own
  // document also its source and frame.
  void Retarget() {
    shields_request_.url = request_.url;
    shields_request_.source =
        request_.request_initiator && !request_.request_initiator->opaque()
            ? request_.request_initiator->GetURL()
            : factory_->TopFrameURL(request_);
    if (shields_request_.type == "main_frame") {
      shields_request_.source = request_.url;
      shields_request_.frame_url = request_.url;
    }
  }

  // A navigation's own document is ShieldsDocumentThrottle's to block, with the page that says
  // so; any other document request (a prefetch) is blocked here.
  bool BlocksDocument() const {
    return shields_request_.type != "main_frame" || !factory_->is_navigation_;
  }

  // Decides request_.url, then loads it, refuses it, serves a stub or redirects.
  void Decide() {
    Retarget();
    if (shields_request_.type == "main_frame" &&
        !ShieldsService::Get().IsActiveFor(request_.url)) {
      StartTarget();
      return;
    }
    if (!engine_) {
      StartTarget();
      return;
    }
    shields::MatchOnPool(
        engine_, shields_request_,
        base::BindOnce(&InProgressRequest::OnDecided, weak_factory_.GetWeakPtr()));
  }

  void OnDecided(shields::Decision decision) {
    if (!BlocksDocument() && decision.should_block) {
      decision.should_block = false;
      decision.redirect.clear();
    }
    factory_->Log(shields::LogEntry(*engine_, shields_request_, decision,
                                    shields::DecisionName(decision)));
    if (decision.should_block) {
      if (!decision.redirect.empty() && ServeStub(decision.redirect)) {
        return;
      }
      Fail(net::ERR_BLOCKED_BY_CLIENT);
      return;
    }
    if (decision.rewritten_url.is_valid() && ++redirects_ <= kMaxRedirects) {
      RedirectTo(decision.rewritten_url);
      return;
    }
    StartTarget();
  }

  void OnRedirectDecided(net::RedirectInfo redirect_info,
                         network::mojom::URLResponseHeadPtr head,
                         shields::Decision decision) {
    shields::Request next = shields_request_;
    next.url = redirect_info.new_url;
    if (shields_request_.type == "main_frame") {
      next.source = next.url;
      next.frame_url = next.url;
    }
    if (!BlocksDocument() && decision.should_block) {
      // ShieldsDocumentThrottle sees the redirect next and shows its page.
      decision.should_block = false;
      decision.redirect.clear();
    }
    factory_->Log(
        shields::LogEntry(*engine_, next, decision, shields::DecisionName(decision)));
    if (decision.should_block) {
      Fail(net::ERR_BLOCKED_BY_CLIENT);
      return;
    }
    if (decision.rewritten_url.is_valid() &&
        url::IsSameOriginWith(decision.rewritten_url, redirect_info.new_url)) {
      redirect_info.new_url = decision.rewritten_url;
    }
    target_client_receiver_.Resume();
    pending_network_redirect_ = redirect_info.new_url;
    client_->OnReceiveRedirect(redirect_info, std::move(head));
  }

  void StartTarget() {
    target_loader_.reset();
    target_client_receiver_.reset();
    factory_->target_->CreateLoaderAndStart(
        target_loader_.BindNewPipeAndPassReceiver(), request_id_, options_, request_,
        target_client_receiver_.BindNewPipeAndPassRemote(), traffic_annotation_);
    target_client_receiver_.set_disconnect_handler(base::BindOnce(
        &InProgressRequest::Fail, base::Unretained(this), net::ERR_ABORTED));
  }

  // Answers with the redirect resource instead of loading: Chromium refuses a subresource
  // redirect to a data: URL, so its body is served as this response.
  bool ServeStub(const std::string& data_url) {
    std::string mime_type;
    std::string charset;
    std::string data;
    if (!net::DataURL::Parse(GURL(data_url), &mime_type, &charset, &data)) {
      return false;
    }
    mojo::ScopedDataPipeProducerHandle producer;
    mojo::ScopedDataPipeConsumerHandle consumer;
    if (mojo::CreateDataPipe(std::max<uint32_t>(static_cast<uint32_t>(data.size()), 1u),
                             producer, consumer) != MOJO_RESULT_OK) {
      return false;
    }
    if (!data.empty() &&
        producer->WriteAllData(base::as_byte_span(data)) != MOJO_RESULT_OK) {
      return false;
    }
    producer.reset();
    auto head = network::mojom::URLResponseHead::New();
    head->mime_type = mime_type;
    head->charset = charset;
    head->content_length = static_cast<int64_t>(data.size());
    head->headers = base::MakeRefCounted<net::HttpResponseHeaders>(
        net::HttpUtil::AssembleRawHeaders(base::StringPrintf(
            "HTTP/1.1 200 OK\nContent-Type: %s\nAccess-Control-Allow-Origin: *\n\n",
            mime_type.c_str())));
    client_->OnReceiveResponse(std::move(head), std::move(consumer), std::nullopt);
    network::URLLoaderCompletionStatus status(net::OK);
    status.decoded_body_length = base::ByteSize(data.size());
    client_->OnComplete(status);
    Finish();
    return true;
  }

  // A redirect of Shields' own ($removeparam), as the network would send one.
  void RedirectTo(const GURL& url) {
    constexpr int kStatus = net::HTTP_TEMPORARY_REDIRECT;
    net::RedirectInfo redirect_info = net::RedirectInfo::ComputeRedirectInfo(
        request_.method, request_.url, request_.site_for_cookies,
        request_.update_first_party_url_on_redirect
            ? net::RedirectInfo::FirstPartyURLPolicy::UPDATE_URL_ON_REDIRECT
            : net::RedirectInfo::FirstPartyURLPolicy::NEVER_CHANGE_URL,
        request_.referrer_policy, request_.referrer.spec(), request_.request_initiator,
        kStatus, url, /*referrer_policy_header=*/std::nullopt,
        /*insecure_scheme_was_upgraded=*/false, /*copy_fragment=*/false);
    auto head = network::mojom::URLResponseHead::New();
    head->headers = base::MakeRefCounted<net::HttpResponseHeaders>(
        net::HttpUtil::AssembleRawHeaders(base::StringPrintf(
            "HTTP/1.1 %i Internal Redirect\nLocation: %s\n"
            "Non-Authoritative-Reason: Refrax Shields\n\n",
            kStatus, url.spec().c_str())));
    head->encoded_data_length = 0;
    pending_shields_redirect_ = url;
    client_->OnReceiveRedirect(redirect_info, std::move(head));
  }

  // Adds the policies $csp rules give this document, both to the headers and to what the
  // network service already parsed from them, which is what the renderer enforces.
  void AddContentSecurityPolicy(network::mojom::URLResponseHead& head) {
    const std::string csp = shields::CspDirectives(*engine_, shields_request_);
    if (csp.empty()) {
      return;
    }
    head.headers->AddHeader("Content-Security-Policy", csp);
    if (head.parsed_headers) {
      for (auto& policy : network::ParseContentSecurityPolicies(
               csp, network::mojom::ContentSecurityPolicyType::kEnforce,
               network::mojom::ContentSecurityPolicySource::kHTTP, request_.url)) {
        head.parsed_headers->content_security_policy.push_back(std::move(policy));
      }
    }
    shields::Decision decision;
    shields::Request request = shields_request_;
    base::DictValue entry = shields::LogEntry(*engine_, request, decision, "csp");
    entry.Set("csp", csp);
    factory_->Log(std::move(entry));
  }

  void Fail(int error) {
    if (client_.is_bound()) {
      client_->OnComplete(network::URLLoaderCompletionStatus(error));
    }
    Finish();
  }

  // Deletes this.
  void Finish() { factory_->RemoveRequest(this); }

  const raw_ptr<ShieldsURLLoaderFactory> factory_;
  mojo::Receiver<network::mojom::URLLoader> loader_receiver_;
  const int32_t request_id_;
  const uint32_t options_;
  network::ResourceRequest request_;
  mojo::Remote<network::mojom::URLLoaderClient> client_;
  const net::MutableNetworkTrafficAnnotationTag traffic_annotation_;
  const scoped_refptr<ShieldsEngineRef> engine_;
  shields::Request shields_request_;

  mojo::Remote<network::mojom::URLLoader> target_loader_;
  mojo::Receiver<network::mojom::URLLoaderClient> target_client_receiver_{this};
  // The location of a redirect the requester has been told about and not yet followed.
  GURL pending_shields_redirect_;
  GURL pending_network_redirect_;
  // Where the network's last redirect pointed, before any rewrite.
  GURL redirect_target_;
  int redirects_ = 0;

  base::WeakPtrFactory<InProgressRequest> weak_factory_{this};
};

// static
void ShieldsURLLoaderFactory::Install(
    content::BrowserContext* browser_context,
    content::RenderFrameHost* frame,
    content::ContentBrowserClient::URLLoaderFactoryType type,
    const url::Origin& request_initiator,
    network::URLLoaderFactoryBuilder& factory_builder) {
  using Type = content::ContentBrowserClient::URLLoaderFactoryType;
  if (type == Type::kDownload) {
    return;
  }
  auto [receiver, target] = factory_builder.Append();
  // Owned by its receivers.
  new ShieldsURLLoaderFactory(
      browser_context, frame ? std::optional(frame->GetGlobalId()) : std::nullopt,
      type == Type::kNavigation, request_initiator, std::move(receiver), std::move(target));
}

ShieldsURLLoaderFactory::ShieldsURLLoaderFactory(
    const content::BrowserContext* browser_context,
    std::optional<content::GlobalRenderFrameHostId> frame,
    bool is_navigation,
    const url::Origin& request_initiator,
    mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
    mojo::PendingRemote<network::mojom::URLLoaderFactory> target)
    : browser_context_(browser_context),
      frame_(frame),
      is_navigation_(is_navigation),
      request_initiator_(request_initiator),
      target_(std::move(target)) {
  receivers_.Add(this, std::move(receiver));
  receivers_.set_disconnect_handler(base::BindRepeating(
      &ShieldsURLLoaderFactory::MaybeDestroy, weak_factory_.GetWeakPtr()));
  target_.set_disconnect_handler(base::BindOnce(
      [](base::WeakPtr<ShieldsURLLoaderFactory> self) {
        if (self) {
          self->receivers_.Clear();
          self->MaybeDestroy();
        }
      },
      weak_factory_.GetWeakPtr()));
}

ShieldsURLLoaderFactory::~ShieldsURLLoaderFactory() = default;

void ShieldsURLLoaderFactory::CreateLoaderAndStart(
    mojo::PendingReceiver<network::mojom::URLLoader> loader,
    int32_t request_id,
    uint32_t options,
    const network::ResourceRequest& request,
    mojo::PendingRemote<network::mojom::URLLoaderClient> client,
    const net::MutableNetworkTrafficAnnotationTag& traffic_annotation) {
  const bool main_frame =
      request.destination == network::mojom::RequestDestination::kDocument &&
      request.is_outermost_main_frame;
  scoped_refptr<ShieldsEngineRef> engine;
  if (ShieldsService::Get().IsActiveFor(main_frame ? request.url : TopFrameURL(request))) {
    engine = ShieldsService::Get().engine();
  }
  if (!engine) {
    // Nothing to decide: the request goes straight to the network.
    target_->CreateLoaderAndStart(std::move(loader), request_id, options, request,
                                  std::move(client), traffic_annotation);
    return;
  }
  auto in_progress = std::make_unique<InProgressRequest>(
      this, std::move(loader), request_id, options, request, std::move(client),
      traffic_annotation, std::move(engine));
  InProgressRequest* started = in_progress.get();
  requests_.insert(std::move(in_progress));
  started->Start();
}

void ShieldsURLLoaderFactory::Clone(
    mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver) {
  receivers_.Add(this, std::move(receiver));
}

GURL ShieldsURLLoaderFactory::TopFrameURL(const network::ResourceRequest& request) const {
  if (content::RenderFrameHost* frame = FrameFor(frame_)) {
    return frame->GetOutermostMainFrame()->GetLastCommittedURL();
  }
  // A worker without a frame: its own origin stands in for the page.
  return request_initiator_.opaque() ? GURL() : request_initiator_.GetURL();
}

GURL ShieldsURLLoaderFactory::FrameURL() const {
  content::RenderFrameHost* frame = FrameFor(frame_);
  return frame ? frame->GetLastCommittedURL() : GURL();
}

void ShieldsURLLoaderFactory::Log(base::DictValue entry) const {
  if (content::RenderFrameHost* frame = FrameFor(frame_)) {
    PageShields::LogFor(frame, std::move(entry));
  } else if (!frame_) {
    PageShields::LogForWorker(browser_context_, request_initiator_, std::move(entry));
  }
}

void ShieldsURLLoaderFactory::RemoveRequest(InProgressRequest* request) {
  auto it = requests_.find(request);
  if (it != requests_.end()) {
    requests_.erase(it);
  }
  MaybeDestroy();
}

void ShieldsURLLoaderFactory::MaybeDestroy() {
  if (receivers_.empty() && requests_.empty()) {
    delete this;
  }
}

bool ShieldsFiltersConnections(content::RenderFrameHost* frame) {
  if (!frame) {
    return ShieldsService::Get().engine() != nullptr;
  }
  return ShieldsService::Get().IsActiveFor(
      frame->GetOutermostMainFrame()->GetLastCommittedURL());
}

void ShieldsDecideConnection(content::RenderFrameHost* frame,
                             const url::Origin& origin,
                             const GURL& url,
                             std::string_view type,
                             base::OnceCallback<void(bool allowed)> done) {
  const GURL top = frame ? frame->GetOutermostMainFrame()->GetLastCommittedURL()
                         : (origin.opaque() ? GURL() : origin.GetURL());
  scoped_refptr<ShieldsEngineRef> engine = ShieldsService::Get().engine();
  if (!engine || !ShieldsService::Get().IsActiveFor(top)) {
    std::move(done).Run(true);
    return;
  }
  shields::Request request;
  request.url = url;
  request.type = std::string(type);
  request.method = "GET";
  request.source = frame ? frame->GetLastCommittedURL() : top;
  request.frame_url = frame ? frame->GetLastCommittedURL() : GURL();
  // adblock-rust matches ws: and wss: as their http equivalents.
  if (url.SchemeIs("ws") || url.SchemeIs("wss")) {
    GURL::Replacements replacements;
    replacements.SetSchemeStr(url.SchemeIs("wss") ? "https" : "http");
    request.url = url.ReplaceComponents(replacements);
  }
  const std::optional<content::GlobalRenderFrameHostId> frame_id =
      frame ? std::optional(frame->GetGlobalId()) : std::nullopt;
  const content::BrowserContext* browser_context = frame ? frame->GetBrowserContext() : nullptr;
  shields::MatchOnPool(
      engine, request,
      base::BindOnce(
          [](scoped_refptr<ShieldsEngineRef> engine, shields::Request request,
             std::optional<content::GlobalRenderFrameHostId> frame_id,
             const content::BrowserContext* browser_context, url::Origin origin,
             base::OnceCallback<void(bool)> done, shields::Decision decision) {
            base::DictValue entry =
                shields::LogEntry(*engine, request, decision, shields::DecisionName(decision));
            if (content::RenderFrameHost* frame = FrameFor(frame_id)) {
              PageShields::LogFor(frame, std::move(entry));
            } else if (!frame_id) {
              PageShields::LogForWorker(browser_context, origin, std::move(entry));
            }
            std::move(done).Run(!decision.should_block);
          },
          engine, request, frame_id, browser_context, origin, std::move(done)));
}

}  // namespace refrax
