// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_ENGINE_REQUESTS_H_
#define REFRAX_HOST_ENGINE_REQUESTS_H_

#include <string>
#include <utility>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/sequence_checker.h"

namespace refrax {

namespace mojom {
class EngineClient;
}  // namespace mojom

// The host's requests to Refrax outside any page (CONTRACT.md §4.6), on the UI thread.
//
// Chromium asks for some of what it needs while the browser process starts, before the client
// has connected (the storage key: see SecretKeyProvider), so a request waits for the client.
// Each is answered exactly once: with Refrax's answer, or with an empty string when the client
// goes away first.
class EngineRequests {
 public:
  using Reply = base::OnceCallback<void(const std::string& answer)>;

  static EngineRequests& Get();

  EngineRequests(const EngineRequests&) = delete;
  EngineRequests& operator=(const EngineRequests&) = delete;

  // Sends the contract's EngineRequest `request`, now or once the client connects.
  void Send(std::string request, Reply reply);

  // The client to send through, until Disconnect; sends every waiting request.
  void Connect(mojom::EngineClient* client);
  // Answers every waiting request with an empty string. Requests already sent are answered by
  // the client's pipe closing.
  void Disconnect();

 private:
  friend class base::NoDestructor<EngineRequests>;

  EngineRequests();
  ~EngineRequests();

  void SendNow(std::string request, Reply reply);

  raw_ptr<mojom::EngineClient> client_ = nullptr;
  std::vector<std::pair<std::string, Reply>> waiting_;
  SEQUENCE_CHECKER(sequence_checker_);
};

}  // namespace refrax

#endif  // REFRAX_HOST_ENGINE_REQUESTS_H_
