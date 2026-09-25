// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/engine_connection.h"

#include <mach/mach.h>

#include "base/apple/mach_logging.h"
#include "base/mac/scoped_mach_msg_destroy.h"
#include "base/memory/ptr_util.h"
#include "mojo/public/cpp/platform/named_platform_channel.h"
#include "mojo/public/cpp/platform/platform_channel.h"
#include "refrax/common/bootstrap.h"

namespace refrax {

EngineConnection::EngineConnection() = default;
EngineConnection::~EngineConnection() = default;

// static
std::unique_ptr<EngineConnection> EngineConnection::Connect(
    const std::string& name) {
  // As an app shim does with the browser (AppShimController::ConnectToBrowser), in reverse: the
  // client listens, and the host sends it the send right of a fresh channel in a raw Mach
  // message, so the client can check who sent it before any Mojo traffic.
  mojo::PlatformChannelEndpoint server =
      mojo::NamedPlatformChannel::ConnectToServer(name);
  if (!server.is_valid()) {
    return nullptr;
  }

  mojo::PlatformChannel channel;
  mach_msg_base_t message{};
  base::ScopedMachMsgDestroy scoped_message(&message.header);
  message.header.msgh_id = kBootstrapMessageID;
  message.header.msgh_bits =
      MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND, MACH_MSG_TYPE_MOVE_SEND);
  message.header.msgh_size = sizeof(message);
  message.header.msgh_local_port =
      channel.TakeLocalEndpoint().TakePlatformHandle().ReleaseMachSendRight();
  message.header.msgh_remote_port =
      server.TakePlatformHandle().ReleaseMachSendRight();
  kern_return_t kr = mach_msg_send(&message.header);
  if (kr != KERN_SUCCESS) {
    MACH_LOG(ERROR, kr) << "mach_msg_send";
    return nullptr;
  }
  scoped_message.Disarm();

  auto connection = base::WrapUnique(new EngineConnection());
  connection->pipe_ =
      connection->connection_.Connect(channel.TakeRemoteEndpoint());
  if (!connection->pipe_.is_valid()) {
    return nullptr;
  }
  return connection;
}

}  // namespace refrax
