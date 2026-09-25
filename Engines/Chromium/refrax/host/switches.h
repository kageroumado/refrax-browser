// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_SWITCHES_H_
#define REFRAX_HOST_SWITCHES_H_

namespace refrax::switches {

// The Mach bootstrap name of the client's acceptor. Its presence makes this browser process a
// Refrax engine host.
extern const char kRefraxBootstrap[];

}  // namespace refrax::switches

#endif  // REFRAX_HOST_SWITCHES_H_
