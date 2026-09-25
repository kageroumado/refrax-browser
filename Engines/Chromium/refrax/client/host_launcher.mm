// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/client/host_launcher.h"

#import <AppKit/AppKit.h>
#include <bsm/libbsm.h>
#include <mach/mach.h>
#import <Security/Security.h>

#include "base/apple/bridging.h"
#include "base/apple/dispatch_source.h"
#include "base/apple/foundation_util.h"
#include "base/apple/mach_logging.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/functional/bind.h"
#include "base/mac/scoped_mach_msg_destroy.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/uuid.h"
#include "mojo/public/cpp/platform/named_platform_channel.h"
#include "refrax/common/bootstrap.h"

namespace refrax {

namespace {

// The Team ID that signed this process (Refrax), or nil when it is unsigned.
NSString* OwnTeamIdentifier() {
  base::apple::ScopedCFTypeRef<SecCodeRef> code;
  base::apple::ScopedCFTypeRef<SecStaticCodeRef> static_code;
  base::apple::ScopedCFTypeRef<CFDictionaryRef> info;
  if (SecCodeCopySelf(kSecCSDefaultFlags, code.InitializeInto()) != errSecSuccess ||
      SecCodeCopyStaticCode(code.get(), kSecCSDefaultFlags,
                            static_code.InitializeInto()) != errSecSuccess ||
      SecCodeCopySigningInformation(static_code.get(), kSecCSSigningInformation,
                                    info.InitializeInto()) != errSecSuccess) {
    return nil;
  }
  return base::apple::ObjCCast<NSString>(
      base::apple::CFToNSPtrCast(info.get())[base::apple::CFToNSPtrCast(
          kSecCodeInfoTeamIdentifier)]);
}

}  // namespace

HostLauncher::HostLauncher() = default;

HostLauncher::~HostLauncher() {
  source_.reset();
  server_endpoint_.reset();
}

void HostLauncher::Launch(const base::FilePath& host_app,
                          std::vector<std::string> arguments,
                          Callback callback) {
  callback_ = std::move(callback);
  service_name_ = "website.refrax.engine.chromium." +
                  base::Uuid::GenerateRandomV4().AsLowercaseString();

  mojo::NamedPlatformChannel::Options options;
  options.server_name = service_name_;
  mojo::NamedPlatformChannel channel(options);
  server_endpoint_ = channel.TakeServerEndpoint();
  if (!server_endpoint_.is_valid()) {
    Finish({}, "Could not register the engine's bootstrap service.");
    return;
  }
  port_ = server_endpoint_.platform_handle().GetMachReceiveRight().get();
  main_task_runner_ = base::SingleThreadTaskRunner::GetCurrentDefault();
  source_ = std::make_unique<base::apple::DispatchSource>(
      service_name_.c_str(), port_, ^{
        HandleRequest();
      });
  source_->Resume();

  NSBundle* bundle = [NSBundle bundleWithPath:base::apple::FilePathToNSString(host_app)];
  NSURL* executable = bundle.executableURL;
  if (!executable) {
    Finish({}, "The engine's host app is missing.");
    return;
  }
  NSTask* task = [[NSTask alloc] init];
  task.executableURL = executable;
  NSMutableArray<NSString*>* task_arguments = [NSMutableArray array];
  [task_arguments addObject:[NSString stringWithFormat:@"--refrax-bootstrap=%s",
                                                       service_name_.c_str()]];
  for (const std::string& argument : arguments) {
    [task_arguments addObject:base::SysUTF8ToNSString(argument)];
  }
  task.arguments = task_arguments;
  // A host that dies before it connects would otherwise leave the engine starting forever.
  scoped_refptr<base::SingleThreadTaskRunner> main_task_runner = main_task_runner_;
  base::WeakPtr<HostLauncher> weak_this = weak_factory_.GetWeakPtr();
  task.terminationHandler = ^(NSTask* terminated) {
    int status = terminated.terminationStatus;
    main_task_runner->PostTask(
        FROM_HERE, base::BindOnce(&HostLauncher::OnHostExited, weak_this, status));
  };
  NSError* error = nil;
  if (![task launchAndReturnError:&error]) {
    Finish({}, base::SysNSStringToUTF8(error.localizedDescription));
    return;
  }
  pid_ = task.processIdentifier;
}

void HostLauncher::HandleRequest() {
  // Runs on the dispatch source's queue; only the result hops to the main thread.
  struct : mach_msg_base_t {
    mach_msg_audit_trailer_t trailer;
  } request{};
  request.header.msgh_size = sizeof(request);
  request.header.msgh_local_port = port_;
  kern_return_t kr = mach_msg(
      &request.header,
      MACH_RCV_MSG | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
          MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
      0, sizeof(request), port_, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
  if (kr != KERN_SUCCESS) {
    MACH_LOG(ERROR, kr) << "mach_msg";
    return;
  }
  base::ScopedMachMsgDestroy scoped_message(&request.header);
  if (request.header.msgh_id != kBootstrapMessageID ||
      request.header.msgh_size != sizeof(mach_msg_base_t)) {
    return;
  }
  audit_token_t token = request.trailer.msgh_audit;
  mojo::PlatformChannelEndpoint endpoint(mojo::PlatformHandle(
      base::apple::ScopedMachSendRight(request.header.msgh_remote_port)));
  scoped_message.Disarm();

  main_task_runner_->PostTask(
      FROM_HERE, base::BindOnce(&HostLauncher::OnRequest, weak_factory_.GetWeakPtr(),
                                std::move(endpoint), token));
}

void HostLauncher::OnRequest(mojo::PlatformChannelEndpoint endpoint,
                             audit_token_t token) {
  if (!callback_ || !IsLaunchedHost(token)) {
    // Someone else found the service name; keep waiting for the real host.
    return;
  }
  // One host per launcher: stop listening, so the name is gone once the host has it.
  source_.reset();
  server_endpoint_.reset();
  Finish(std::move(endpoint), {});
}

bool HostLauncher::IsLaunchedHost(const audit_token_t& token) const {
  if (pid_ == 0 || audit_token_to_pid(token) != pid_) {
    return false;
  }
  NSString* team = OwnTeamIdentifier();
  if (!team) {
    // An unsigned Refrax (a local build) can't pin a signature; the pid still has to match.
    return true;
  }
  NSData* token_data = [NSData dataWithBytes:&token length:sizeof(token)];
  base::apple::ScopedCFTypeRef<SecCodeRef> code;
  if (SecCodeCopyGuestWithAttributes(
          nullptr,
          base::apple::NSToCFPtrCast(@{
            base::apple::CFToNSPtrCast(kSecGuestAttributeAudit) : token_data
          }),
          kSecCSDefaultFlags, code.InitializeInto()) != errSecSuccess) {
    return false;
  }
  NSString* text = [NSString
      stringWithFormat:@"anchor apple generic and certificate leaf[subject.OU] = \"%@\"",
                       team];
  base::apple::ScopedCFTypeRef<SecRequirementRef> requirement;
  if (SecRequirementCreateWithString(base::apple::NSToCFPtrCast(text),
                                     kSecCSDefaultFlags,
                                     requirement.InitializeInto()) != errSecSuccess) {
    return false;
  }
  return SecCodeCheckValidity(code.get(), kSecCSDefaultFlags, requirement.get()) ==
         errSecSuccess;
}

void HostLauncher::OnHostExited(int status) {
  Finish({}, "The Chromium host exited during startup (status " +
                 base::NumberToString(status) + ").");
}

void HostLauncher::Finish(mojo::PlatformChannelEndpoint endpoint,
                          std::string error) {
  if (callback_) {
    std::move(callback_).Run(std::move(endpoint), std::move(error));
  }
}

}  // namespace refrax
