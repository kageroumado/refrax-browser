// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_ENGINE_CONNECTION_H_
#define REFRAX_HOST_ENGINE_CONNECTION_H_

#include <memory>
#include <string>

#include "mojo/public/cpp/system/isolated_connection.h"
#include "mojo/public/cpp/system/message_pipe.h"

namespace refrax {

// The host's end of the Mojo connection to the client. Closing it disconnects the client.
class EngineConnection {
 public:
  // Connects to the client's bootstrap service `name`; nullptr when it isn't there.
  static std::unique_ptr<EngineConnection> Connect(const std::string& name);

  EngineConnection(const EngineConnection&) = delete;
  EngineConnection& operator=(const EngineConnection&) = delete;
  ~EngineConnection();

  mojo::ScopedMessagePipeHandle TakePipe() { return std::move(pipe_); }

 private:
  EngineConnection();

  mojo::IsolatedConnection connection_;
  mojo::ScopedMessagePipeHandle pipe_;
};

}  // namespace refrax

#endif  // REFRAX_HOST_ENGINE_CONNECTION_H_
