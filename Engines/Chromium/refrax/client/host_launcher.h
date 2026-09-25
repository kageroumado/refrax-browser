// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_CLIENT_HOST_LAUNCHER_H_
#define REFRAX_CLIENT_HOST_LAUNCHER_H_

#include <bsm/libbsm.h>
#include <mach/mach.h>

#include <memory>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "mojo/public/cpp/platform/platform_channel_endpoint.h"
#include "mojo/public/cpp/platform/platform_channel_server_endpoint.h"

namespace base::apple {
class DispatchSource;
}

namespace refrax {

// Launches the host app and returns the Mojo channel endpoint it connects with. The channel is
// a Mach bootstrap service under a random name, passed to the host on its command line; only
// a message from the launched process, signed by Refrax's team, is accepted.
class HostLauncher {
 public:
  // Called once on the main thread: a valid endpoint, or an invalid one and a reason.
  using Callback =
      base::OnceCallback<void(mojo::PlatformChannelEndpoint, std::string error)>;

  HostLauncher();
  HostLauncher(const HostLauncher&) = delete;
  HostLauncher& operator=(const HostLauncher&) = delete;
  ~HostLauncher();

  void Launch(const base::FilePath& host_app,
              std::vector<std::string> arguments,
              Callback callback);

  // The launched host's process id, or 0.
  pid_t pid() const { return pid_; }

 private:
  // On the dispatch source's queue: receives one bootstrap message.
  void HandleRequest();
  void OnRequest(mojo::PlatformChannelEndpoint endpoint, audit_token_t token);
  // The host exited; fails the launch if it never connected.
  void OnHostExited(int status);
  void Finish(mojo::PlatformChannelEndpoint endpoint, std::string error);
  bool IsLaunchedHost(const audit_token_t& token) const;

  std::string service_name_;
  mojo::PlatformChannelServerEndpoint server_endpoint_;
  mach_port_t port_ = MACH_PORT_NULL;
  scoped_refptr<base::SingleThreadTaskRunner> main_task_runner_;
  std::unique_ptr<base::apple::DispatchSource> source_;
  pid_t pid_ = 0;
  Callback callback_;
  base::WeakPtrFactory<HostLauncher> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_CLIENT_HOST_LAUNCHER_H_
