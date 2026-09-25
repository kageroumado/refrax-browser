// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_COMMON_BOOTSTRAP_H_
#define REFRAX_COMMON_BOOTSTRAP_H_

#include <mach/message.h>

namespace refrax {

// The client registers a Mach bootstrap service and launches the host with its name; the host
// sends one message with this id whose reply port is the send right of a new Mojo channel.
// The client accepts it only from the host it launched (audit token pid and code signature).
inline constexpr mach_msg_id_t kBootstrapMessageID = 'RfxB';

}  // namespace refrax

#endif  // REFRAX_COMMON_BOOTSTRAP_H_
