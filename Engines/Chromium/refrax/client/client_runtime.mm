// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/client/client_runtime.h"

#import <AppKit/AppKit.h>
#include <objc/runtime.h>

#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/mac/scoped_sending_event.h"
#include "base/message_loop/message_pump_apple.h"
#include "base/no_destructor.h"
#include "base/task/current_thread.h"
#include "base/task/single_thread_task_executor.h"
#include "base/task/thread_pool/thread_pool_instance.h"
#include "base/threading/thread.h"
#include "components/remote_cocoa/app_shim/application_bridge.h"
#include "content/public/browser/remote_cocoa.h"
#include "content/public/common/content_client.h"
#include "mojo/core/embedder/embedder.h"
#include "mojo/core/embedder/scoped_ipc_support.h"
#include "ui/accelerated_widget_mac/window_resize_helper_mac.h"
#include "ui/display/screen.h"

namespace refrax {

namespace {

// -[NSApplication isHandlingSendEvent] / -setHandlingSendEvent: for an NSApp that isn't a
// Chromium application: the flag base::mac::ScopedSendingEvent flips around nested event loops
// (a <select> popup's menu), stored on the application object.
const char kHandlingSendEventKey = 0;

BOOL IsHandlingSendEvent(id self, SEL) {
  return [objc_getAssociatedObject(self, &kHandlingSendEventKey) boolValue];
}

void SetHandlingSendEvent(id self, SEL, BOOL handling) {
  objc_setAssociatedObject(self, &kHandlingSendEventKey, @(handling),
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Gives Refrax's application class the protocols Chromium's Cocoa code casts NSApp to, without
// Refrax knowing about Chromium. Must run before the main message pump is created: that is
// when base picks the pump for a CrAppProtocol application.
void AdoptCrAppProtocols() {
  Class app_class = [NSApp class];
  if (![NSApp respondsToSelector:@selector(isHandlingSendEvent)]) {
    class_addMethod(app_class, @selector(isHandlingSendEvent),
                    reinterpret_cast<IMP>(IsHandlingSendEvent), "c@:");
  }
  if (![NSApp respondsToSelector:@selector(setHandlingSendEvent:)]) {
    class_addMethod(app_class, @selector(setHandlingSendEvent:),
                    reinterpret_cast<IMP>(SetHandlingSendEvent), "v@:c");
  }
  class_addProtocol(app_class, @protocol(CrAppProtocol));
  class_addProtocol(app_class, @protocol(CrAppControlProtocol));
}

// content's Cocoa views ask the content client for a few resources (the drag-image
// fallback); the defaults are enough.
class ClientContentClient : public content::ContentClient {};

struct Runtime {
  Runtime() {
    // A non-empty --type marks this as a helper-side process for content's Cocoa code: the
    // browser-process occlusion checker would otherwise swizzle -[NSWindow
    // orderWindow:relativeTo:] in all of Refrax.
    base::CommandLine::Init(0, nullptr);
    base::CommandLine::ForCurrentProcess()->AppendSwitchASCII("type",
                                                              "refrax-client");

    AdoptCrAppProtocols();

    // Mojo's transport features must match the host's, and both run the same build with no
    // field trials, so the defaults agree.
    base::FeatureList::InitInstance(std::string(), std::string());

    mojo::core::InitFeatures();
    mojo::core::Configuration mojo_configuration;
    mojo_configuration.is_broker_process = true;
    mojo::core::Init(mojo_configuration);

    io_thread.StartWithOptions(
        base::Thread::Options(base::MessagePumpType::IO, 0));
    ipc_support.emplace(io_thread.task_runner(),
                        mojo::core::ScopedIPCSupport::ShutdownPolicy::FAST);

    // Refrax already runs -[NSApplication run]: attach base's main-thread task runner to it
    // (patches/base-mac-attach-pump.patch) instead of running a loop of our own.
    main_executor.emplace(base::MessagePumpType::UI, /*is_main_thread=*/true);
    base::CurrentUIThread::Get()->Attach();

    ui::WindowResizeHelperMac::Get()->Init(
        base::SingleThreadTaskRunner::GetCurrentDefault());
    screen.emplace();
    content::SetContentClient(&content_client);

    remote_cocoa::ApplicationBridge::SetIsOutOfProcessAppShim();
    remote_cocoa::ApplicationBridge::Get()->SetContentNSViewCreateCallbacks(
        base::BindRepeating([](uint64_t view_id,
                               mojo::ScopedInterfaceEndpointHandle host,
                               mojo::ScopedInterfaceEndpointHandle view) {
          remote_cocoa::CreateRenderWidgetHostNSView(
              view_id, std::move(host), std::move(view), {});
        }),
        base::BindRepeating(&remote_cocoa::CreateWebContentsNSView));

    base::ThreadPoolInstance::CreateAndStartWithDefaultParams("RefraxChromium");
  }

  base::AtExitManager at_exit;
  base::Thread io_thread{"RefraxChromiumIO"};
  std::optional<mojo::core::ScopedIPCSupport> ipc_support;
  std::optional<base::SingleThreadTaskExecutor> main_executor;
  std::optional<display::ScopedNativeScreen> screen;
  ClientContentClient content_client;
};

Runtime& GetRuntime() {
  static base::NoDestructor<Runtime> runtime;
  return *runtime;
}

}  // namespace

// static
void ClientRuntime::EnsureStarted() {
  CHECK([NSThread isMainThread]);
  GetRuntime();
}

// static
scoped_refptr<base::SingleThreadTaskRunner> ClientRuntime::io_task_runner() {
  return GetRuntime().io_thread.task_runner();
}

}  // namespace refrax
