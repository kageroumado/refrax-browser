// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/engine_requests.h"

#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "refrax/common/mojom/engine.mojom.h"

namespace refrax {

// static
EngineRequests& EngineRequests::Get() {
  static base::NoDestructor<EngineRequests> instance;
  return *instance;
}

EngineRequests::EngineRequests() = default;
EngineRequests::~EngineRequests() = default;

void EngineRequests::Send(std::string request, Reply reply) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  if (!client_) {
    waiting_.emplace_back(std::move(request), std::move(reply));
    return;
  }
  SendNow(std::move(request), std::move(reply));
}

void EngineRequests::Connect(mojom::EngineClient* client) {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_ = client;
  for (auto& [request, reply] : std::exchange(waiting_, {})) {
    SendNow(std::move(request), std::move(reply));
  }
}

void EngineRequests::Disconnect() {
  DCHECK_CALLED_ON_VALID_SEQUENCE(sequence_checker_);
  client_ = nullptr;
  for (auto& [request, reply] : std::exchange(waiting_, {})) {
    std::move(reply).Run(std::string());
  }
}

void EngineRequests::SendNow(std::string request, Reply reply) {
  client_->OnRequest(request, mojo::WrapCallbackWithDefaultInvokeIfNotRun(
                                  std::move(reply), std::string()));
}

}  // namespace refrax
