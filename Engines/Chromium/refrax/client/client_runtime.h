// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_CLIENT_CLIENT_RUNTIME_H_
#define REFRAX_CLIENT_CLIENT_RUNTIME_H_

#include "base/memory/scoped_refptr.h"
#include "base/task/single_thread_task_runner.h"

namespace refrax {

// The slice of Chromium the client runs inside Refrax's process: base's task system attached
// to Refrax's running main run loop, Mojo, and remote_cocoa's view bridges. Started once, the
// first time an engine starts, and never torn down: Chromium's globals outlive any one engine.
class ClientRuntime {
 public:
  // Starts the runtime on first use. Main thread only, and only where CanStart() is true.
  static void EnsureStarted();

  // Whether EnsureStarted may run here: the runtime is running, or this is Refrax's main
  // event loop. Starting attaches Chromium's main-thread message pump to that loop, counting
  // exactly one run loop level as already entered; started from a menu's or a modal's nested
  // loop, the pump counts one level too few and aborts the process when that loop exits.
  static bool CanStart();

  static scoped_refptr<base::SingleThreadTaskRunner> io_task_runner();
};

}  // namespace refrax

#endif  // REFRAX_CLIENT_CLIENT_RUNTIME_H_
