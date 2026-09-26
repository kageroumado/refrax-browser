// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import <AppKit/AppKit.h>

#include <cstdlib>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/strings/string_split.h"
#include "base/strings/sys_string_conversions.h"
#include "components/remote_cocoa/app_shim/application_bridge.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "mojo/public/cpp/system/isolated_connection.h"
#include "refrax/client/client_runtime.h"
#import "refrax/client/chromium_page.h"
#include "refrax/client/host_launcher.h"
#include "refrax/common/mojom/engine.mojom.h"
#import "refrax/sdk/RFXEngine.h"

namespace {

NSError* EngineError(NSInteger code, NSString* description) {
  return [NSError errorWithDomain:@"RFXChromiumEngine"
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : description}];
}

std::string ToString(NSData* data) {
  return std::string(static_cast<const char*>(data.bytes), data.length);
}

NSData* ToData(const std::string& string) {
  return [NSData dataWithBytes:string.data() length:string.size()];
}

// The host's command line for the storage Refrax gave the engine.
std::vector<std::string> HostArguments(NSDictionary* configuration) {
  NSURL* storage = [NSURL URLWithString:configuration[@"storageDirectory"]];
  NSURL* userData = [storage URLByAppendingPathComponent:@"Chromium" isDirectory:YES];
  // The network service's sandbox admits the cache directory only if it already exists.
  [NSFileManager.defaultManager createDirectoryAtURL:[userData URLByAppendingPathComponent:@"Cache"]
                         withIntermediateDirectories:YES
                                          attributes:nil
                                               error:nil];
  std::vector<std::string> arguments = {
      "--user-data-dir=" + base::SysNSStringToUTF8(userData.path),
      // Chromium moves caches out of an Application Support user-data-dir; keep them inside the
      // storage Refrax owns.
      "--disk-cache-dir=" +
          base::SysNSStringToUTF8([userData URLByAppendingPathComponent:@"Cache"].path),
      "--no-startup-window",
      "--no-first-run",
      "--no-default-browser-check",
      "--no-error-dialogs",
      // Chrome features that assume every page sits in a Chrome tab strip and crash the host
      // on the engine's pages (tabs::TabInterface::GetFromContents): Reading Mode's
      // soft-navigation observer. Refrax has its own reader.
      "--disable-features=ImmersiveReadAnything",
  };
  if (NSString* log = configuration[@"logFile"]; [log isKindOfClass:NSString.class]) {
    arguments.push_back("--enable-logging");
    arguments.push_back("--log-file=" + base::SysNSStringToUTF8([NSURL URLWithString:log].path));
  }
  if (NSArray* languages = configuration[@"languages"];
      [languages isKindOfClass:NSArray.class] && languages.count > 0) {
    arguments.push_back("--lang=" + base::SysNSStringToUTF8(languages.firstObject));
  }
  // Extra host switches for diagnosing the host, space-separated: --log-net-log=…, --vmodule=….
  if (const char* flags = std::getenv("REFRAX_CHROMIUM_HOST_FLAGS")) {
    for (std::string& flag : base::SplitString(flags, " ", base::TRIM_WHITESPACE,
                                               base::SPLIT_WANT_NONEMPTY)) {
      arguments.push_back(std::move(flag));
    }
  }
  return arguments;
}

}  // namespace

// The Chromium engine's principal class (Engines/CONTRACT.md): runs Chromium's browser process
// as "Refrax Chromium Host.app" inside this bundle and shows its pages through remote_cocoa.
@interface RFXChromiumEngine : NSObject <RFXEngineHost>
- (void)hostDidEmitEvent:(const std::string&)event;
- (void)hostDidRequest:(const std::string&)request reply:(void (^)(NSData* answer))reply;
@end

namespace {

// Delivers the host's events and requests outside any page to the engine's delegate.
class EngineClientImpl : public refrax::mojom::EngineClient {
 public:
  EngineClientImpl(RFXChromiumEngine* engine,
                   mojo::PendingAssociatedReceiver<refrax::mojom::EngineClient> receiver)
      : engine_(engine), receiver_(this, std::move(receiver)) {}

  void OnEvent(const std::string& event) override { [engine_ hostDidEmitEvent:event]; }

  void OnRequest(const std::string& request, OnRequestCallback callback) override {
    // Blocks copy their captures; the Mojo reply is move-only, so it rides in a shared_ptr.
    auto reply = std::make_shared<OnRequestCallback>(std::move(callback));
    [engine_ hostDidRequest:request
                      reply:^(NSData* answer) {
                        if (*reply) {
                          std::move(*reply).Run(ToString(answer));
                        }
                      }];
  }

 private:
  __weak RFXChromiumEngine* engine_;
  mojo::AssociatedReceiver<refrax::mojom::EngineClient> receiver_;
};

}  // namespace

@implementation RFXChromiumEngine {
  std::unique_ptr<refrax::HostLauncher> _launcher;
  std::unique_ptr<mojo::IsolatedConnection> _connection;
  mojo::Remote<refrax::mojom::EngineHost> _host;
  std::unique_ptr<EngineClientImpl> _client;
  NSHashTable<RFXChromiumPage*>* _pages;
  BOOL _terminated;
}

@synthesize delegate = _delegate;

- (instancetype)init {
  if ((self = [super init])) {
    _pages = [NSHashTable weakObjectsHashTable];
  }
  return self;
}

- (void)startWithConfiguration:(NSData*)configuration
                    completion:(void (^)(NSError* _Nullable))completion {
  NSDictionary* parsed = [NSJSONSerialization JSONObjectWithData:configuration options:0 error:nil];
  if (![parsed isKindOfClass:NSDictionary.class] ||
      ![parsed[@"storageDirectory"] isKindOfClass:NSString.class]) {
    completion(EngineError(1, @"The engine configuration is malformed."));
    return;
  }
  if (!refrax::ClientRuntime::CanStart()) {
    // Asked from a nested loop, such as a menu action's: start once Refrax's main event loop
    // runs again (see ClientRuntime::CanStart).
    // Retains the engine: its start always completes.
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
      [self startWithConfiguration:configuration completion:completion];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
    return;
  }
  refrax::ClientRuntime::EnsureStarted();

  NSString* hostPath = [[NSBundle bundleForClass:self.class].bundlePath
      stringByAppendingPathComponent:@"Contents/Helpers/Refrax Chromium Host.app"];
  std::string configurationJSON = ToString(configuration);
  __weak RFXChromiumEngine* weakSelf = self;
  _launcher = std::make_unique<refrax::HostLauncher>();
  _launcher->Launch(
      base::apple::NSStringToFilePath(hostPath), HostArguments(parsed),
      base::BindOnce(
          [](__weak RFXChromiumEngine* weakEngine, std::string configurationJSON,
             void (^completion)(NSError*), mojo::PlatformChannelEndpoint endpoint,
             std::string error) {
            RFXChromiumEngine* engine = weakEngine;
            if (!engine) {
              return;
            }
            if (!endpoint.is_valid()) {
              completion(EngineError(2, base::SysUTF8ToNSString(error)));
              return;
            }
            [engine connectWithEndpoint:std::move(endpoint)
                          configuration:configurationJSON
                             completion:completion];
          },
          weakSelf, std::move(configurationJSON), completion));
}

- (void)connectWithEndpoint:(mojo::PlatformChannelEndpoint)endpoint
              configuration:(const std::string&)configuration
                 completion:(void (^)(NSError*))completion {
  _connection = std::make_unique<mojo::IsolatedConnection>();
  _host.Bind(mojo::PendingRemote<refrax::mojom::EngineHost>(
      _connection->Connect(std::move(endpoint)), 0));
  __weak RFXChromiumEngine* weakSelf = self;
  _host.set_disconnect_handler(base::BindOnce(
      [](__weak RFXChromiumEngine* engine) { [engine hostDidTerminate]; }, weakSelf));

  // The host builds each page's NSViews through this: Chromium's own app-shim bridge.
  mojo::PendingAssociatedRemote<remote_cocoa::mojom::Application> application;
  remote_cocoa::ApplicationBridge::Get()->BindReceiver(
      application.InitWithNewEndpointAndPassReceiver());

  mojo::PendingAssociatedRemote<refrax::mojom::EngineClient> client;
  _client = std::make_unique<EngineClientImpl>(self, client.InitWithNewEndpointAndPassReceiver());

  _host->Start(configuration, std::move(application), std::move(client),
               base::BindOnce(
                   [](void (^completion)(NSError*), const std::optional<std::string>& error) {
                     completion(error ? EngineError(3, base::SysUTF8ToNSString(*error)) : nil);
                   },
                   completion));
}

- (nullable id<RFXEnginePage>)makePageWithSpec:(NSData*)spec
                                         error:(NSError* _Nullable* _Nullable)error {
  if (!_host.is_bound() || _terminated) {
    if (error) {
      *error = EngineError(4, @"The Chromium engine is not running.");
    }
    return nil;
  }
  mojo::PendingAssociatedRemote<refrax::mojom::Page> page;
  auto pageReceiver = page.InitWithNewEndpointAndPassReceiver();
  mojo::PendingAssociatedRemote<refrax::mojom::PageClient> client;
  auto clientReceiver = client.InitWithNewEndpointAndPassReceiver();

  RFXChromiumPage* chromiumPage = [[RFXChromiumPage alloc] initWithPage:std::move(page)
                                                                 client:std::move(clientReceiver)];
  [_pages addObject:chromiumPage];
  __weak RFXChromiumPage* weakPage = chromiumPage;
  _host->CreatePage(ToString(spec), std::move(pageReceiver), std::move(client),
                    base::BindOnce(
                        [](__weak RFXChromiumPage* page, uint64_t containerID) {
                          [page attachToContainerID:containerID];
                        },
                        weakPage));
  return chromiumPage;
}

- (void)applyPolicy:(NSData*)update {
  if (_host.is_bound()) {
    _host->ApplyPolicy(ToString(update));
  }
}

- (void)performCommand:(NSData*)command {
  if (_host.is_bound()) {
    _host->PerformCommand(ToString(command));
  }
}

- (void)hostDidEmitEvent:(const std::string&)event {
  if ([_delegate respondsToSelector:@selector(engineHost:didEmitEvent:)]) {
    [_delegate engineHost:self didEmitEvent:ToData(event)];
  }
}

- (void)hostDidRequest:(const std::string&)request reply:(void (^)(NSData* answer))reply {
  if (![_delegate respondsToSelector:@selector(engineHost:didRequest:reply:)]) {
    reply(ToData(R"({"unavailable":{}})"));
    return;
  }
  [_delegate engineHost:self didRequest:ToData(request) reply:reply];
}

- (void)removeProfile:(NSData*)profile completion:(void (^)(void))completion {
  if (!_host.is_bound()) {
    completion();
    return;
  }
  _host->RemoveProfile(ToString(profile), base::BindOnce(
                                              [](void (^completion)(void)) { completion(); },
                                              completion));
}

- (void)shutdown {
  for (RFXChromiumPage* page in _pages.allObjects) {
    [page close];
  }
  // Closing the pipe quits the host.
  _client.reset();
  _host.reset();
  _connection.reset();
  _launcher.reset();
}

- (void)hostDidTerminate {
  if (_terminated) {
    return;
  }
  _terminated = YES;
  _client.reset();
  _host.reset();
  for (RFXChromiumPage* page in _pages.allObjects) {
    [page hostDidTerminate];
  }
  [_delegate engineHostDidTerminateWithReason:@"The Chromium host process exited."];
}

@end
