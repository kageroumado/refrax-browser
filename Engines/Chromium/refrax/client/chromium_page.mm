// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import "refrax/client/chromium_page.h"

#include <memory>
#include <optional>

#include "base/apple/foundation_util.h"
#include "base/functional/bind.h"
#include "base/strings/sys_string_conversions.h"
#include "components/remote_cocoa/app_shim/ns_view_ids.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/utils/mac/SkCGUtils.h"
#include "ui/base/cocoa/remote_accessibility_api.h"
#include "ui/events/cocoa/cocoa_event_utils.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/size.h"

@class RFXChromiumPage;

@interface RFXChromiumPage ()
- (void)showDevToolsWindowWithID:(uint64_t)viewID title:(NSString*)title;
- (void)closeDevToolsWindow;
- (void)accessibilityElementChanged;
- (void)containerDidMoveToWindow;
- (void)devToolsKeyDown:(NSEvent*)event;
@end

namespace {

NSData* ToData(const std::string& string) {
  return [NSData dataWithBytes:string.data() length:string.size()];
}

std::string ToString(NSData* data) {
  return std::string(static_cast<const char*>(data.bytes), data.length);
}

// What a closed page keeps until the host confirms the close.
struct ClosingPage {
  mojo::AssociatedRemote<refrax::mojom::Page> page;
  std::unique_ptr<remote_cocoa::ScopedNSViewIdMapping> view_id_mapping;
  std::unique_ptr<remote_cocoa::ScopedNSViewIdMapping> devtools_view_id_mapping;
  NSView* __strong container;
  NSView* __strong devtools_container;
};

// A call's reply that will never come: the page closed or its host exited first.
NSError* PageGoneError() {
  return [NSError errorWithDomain:@"RFXChromiumEngine"
                             code:4
                         userInfo:@{
                           NSLocalizedDescriptionKey : @"The page closed before it answered."
                         }];
}

// Delivers the host's page callbacks to the page's delegate, on the main thread where Mojo
// runs them.
class PageClientImpl : public refrax::mojom::PageClient {
 public:
  PageClientImpl(RFXChromiumPage* page,
                 mojo::PendingAssociatedReceiver<refrax::mojom::PageClient> receiver)
      : page_(page), receiver_(this, std::move(receiver)) {}

  void OnEvent(const std::string& event) override {
    RFXChromiumPage* page = page_;
    [page.delegate enginePage:page didEmitEvent:ToData(event)];
  }

  void OnRequest(const std::string& request, OnRequestCallback callback) override {
    RFXChromiumPage* page = page_;
    if (!page.delegate) {
      return;
    }
    // Blocks copy their captures; the Mojo reply is move-only, so it rides in a shared_ptr.
    auto reply = std::make_shared<OnRequestCallback>(std::move(callback));
    [page.delegate enginePage:page
                   didRequest:ToData(request)
                        reply:^(NSData* answer) {
                          if (*reply) {
                            std::move(*reply).Run(ToString(answer));
                          }
                        }];
  }

  void RedispatchKeyEvent(const std::vector<uint8_t>& native_event_data) override {
    NSEvent* event = ui::EventFromData(native_event_data);
    if (event.type == NSEventTypeKeyDown) {
      // Only the menus: offering it to the window's views would hand it straight back to the
      // page's RenderWidgetHostViewCocoa, which claims every key equivalent while focused.
      [NSApp.mainMenu performKeyEquivalent:event];
    }
  }

  void ShowDevToolsWindow(uint64_t container_ns_view_id,
                          const std::string& title,
                          ShowDevToolsWindowCallback callback) override {
    // The window's view is registered before the reply, after which the host builds the
    // frontend's views in it.
    [page_ showDevToolsWindowWithID:container_ns_view_id title:base::SysUTF8ToNSString(title)];
    std::move(callback).Run();
  }

  void CloseDevToolsWindow() override { [page_ closeDevToolsWindow]; }

  void AccessibilityElementChanged() override { [page_ accessibilityElementChanged]; }

  void RedispatchDevToolsKeyEvent(const std::vector<uint8_t>& native_event_data) override {
    NSEvent* event = ui::EventFromData(native_event_data);
    if (event.type == NSEventTypeKeyDown) {
      [page_ devToolsKeyDown:event];
    }
  }

  void OnScriptMessage(const std::string& message,
                       OnScriptMessageCallback callback) override {
    RFXChromiumPage* page = page_;
    if (!page.delegate) {
      return;
    }
    // Blocks copy their captures; the Mojo reply is move-only, so it rides in a shared_ptr.
    auto reply = std::make_shared<OnScriptMessageCallback>(std::move(callback));
    [page.delegate enginePage:page
        didReceiveScriptMessage:ToData(message)
                          reply:^(NSData* answer) {
                            if (*reply) {
                              std::move(*reply).Run(ToString(answer));
                            }
                          }];
  }

 private:
  __weak RFXChromiumPage* page_;
  mojo::AssociatedReceiver<refrax::mojom::PageClient> receiver_;
};

}  // namespace

// The page's view: Chromium's WebContentsViewCocoa becomes its only subview. It tells the host
// its size, since the host lays the page out. To assistive technologies it shows the page's
// accessibility tree, which lives in the host: its one child is a remote element for the
// page's root there, and the subviews (Chromium's views here, which carry no tree) are hidden.
@interface RFXChromiumContainerView : NSView
@property(nonatomic, copy) void (^sizeDidChange)(NSSize size);
// The remote root element, or nil while there is none yet; asking starts fetching it.
@property(nonatomic, copy) id (^accessibilityRoot)(void);
@property(nonatomic, copy) void (^didMoveToWindow)(void);
@end

@implementation RFXChromiumContainerView

@synthesize sizeDidChange = _sizeDidChange;
@synthesize accessibilityRoot = _accessibilityRoot;
@synthesize didMoveToWindow = _didMoveToWindow;

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (_didMoveToWindow) {
    _didMoveToWindow();
  }
}

- (id)remoteRoot {
  return _accessibilityRoot ? _accessibilityRoot() : nil;
}

- (BOOL)isAccessibilityElement {
  return NO;
}

- (NSArray*)accessibilityChildren {
  if (!_accessibilityRoot) {
    return [super accessibilityChildren];
  }
  id root = [self remoteRoot];
  return root ? @[ root ] : @[];
}

- (id)accessibilityHitTest:(NSPoint)point {
  id root = [self remoteRoot];
  return root ? [root accessibilityHitTest:point] : [super accessibilityHitTest:point];
}

- (id)accessibilityFocusedUIElement {
  id root = [self remoteRoot];
  return root ? [root accessibilityFocusedUIElement] : [super accessibilityFocusedUIElement];
}

- (BOOL)isFlipped {
  return YES;
}

- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  if (_sizeDidChange) {
    _sizeDidChange(size);
  }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
  for (NSView* subview in self.subviews) {
    subview.frame = self.bounds;
  }
}

@end

@interface RFXChromiumPage () <NSWindowDelegate>
@end

@implementation RFXChromiumPage {
  mojo::AssociatedRemote<refrax::mojom::Page> _page;
  std::unique_ptr<PageClientImpl> _client;
  std::unique_ptr<remote_cocoa::ScopedNSViewIdMapping> _viewIDMapping;
  RFXChromiumContainerView* _container;
  BOOL _closed;

  // The DevTools window and its content view, registered under the id the host builds the
  // frontend's views with.
  NSWindow* _devToolsWindow;
  RFXChromiumContainerView* _devToolsContainer;
  std::unique_ptr<remote_cocoa::ScopedNSViewIdMapping> _devToolsViewIDMapping;

  // Accessibility: whether an assistive technology has asked, the remote root element once
  // the host has sent its token, and whether a token request is outstanding.
  BOOL _accessibilityStarted;
  // Whether the host was last asked for the full tree (VoiceOver on) or the basic one.
  BOOL _accessibilityScreenReader;
  NSAccessibilityRemoteUIElement* _accessibilityRoot;
  BOOL _fetchingAccessibilityToken;
}

@synthesize delegate = _delegate;

- (instancetype)initWithPage:(mojo::PendingAssociatedRemote<refrax::mojom::Page>)page
                      client:(mojo::PendingAssociatedReceiver<refrax::mojom::PageClient>)
                                 client {
  if ((self = [super init])) {
    _page.Bind(std::move(page));
    _client = std::make_unique<PageClientImpl>(self, std::move(client));
    _container = [[RFXChromiumContainerView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _container.wantsLayer = YES;
    __weak RFXChromiumPage* weakSelf = self;
    _container.sizeDidChange = ^(NSSize size) {
      [weakSelf containerDidResize:size];
    };
    _container.accessibilityRoot = ^id {
      return [weakSelf accessibilityRoot];
    };
    _container.didMoveToWindow = ^{
      [weakSelf containerDidMoveToWindow];
    };
  }
  return self;
}

// MARK: Accessibility

- (id)accessibilityRoot {
  if (_closed) {
    return nil;
  }
  // The host builds accessibility trees only once something reads them: the basic tree for
  // most assistive technologies, the full one while VoiceOver is on.
  const BOOL screenReader = NSWorkspace.sharedWorkspace.voiceOverEnabled;
  if (!_accessibilityStarted || _accessibilityScreenReader != screenReader) {
    _page->EnableAccessibility(screenReader);
    _accessibilityScreenReader = screenReader;
  }
  if (!_accessibilityStarted) {
    _accessibilityStarted = YES;
    _page->SetAccessibilityParent(getpid(),
                                  ui::RemoteAccessibility::GetTokenForLocalElement(_container));
  }
  if (!_accessibilityRoot) {
    [self fetchAccessibilityRoot];
  }
  return _accessibilityRoot;
}

- (void)fetchAccessibilityRoot {
  if (_fetchingAccessibilityToken || _closed) {
    return;
  }
  _fetchingAccessibilityToken = YES;
  __weak RFXChromiumPage* weakSelf = self;
  void (^received)(int32_t, std::vector<uint8_t>) = ^(int32_t pid, std::vector<uint8_t> token) {
    [weakSelf didReceiveAccessibilityToken:token fromProcess:pid];
  };
  _page->GetAccessibilityToken(base::BindOnce(
      [](void (^received)(int32_t, std::vector<uint8_t>), int32_t pid,
         const std::vector<uint8_t>& token) { received(pid, token); },
      received));
}

- (void)didReceiveAccessibilityToken:(const std::vector<uint8_t>&)token fromProcess:(int32_t)pid {
  _fetchingAccessibilityToken = NO;
  if (token.empty() || _closed) {
    return;
  }
  [NSAccessibilityRemoteUIElement registerRemoteUIProcessIdentifier:pid];
  _accessibilityRoot = ui::RemoteAccessibility::GetRemoteElementFromToken(token);
  _accessibilityRoot.windowUIElement = _container.window;
  _accessibilityRoot.topLevelUIElement = _container.window;
  NSAccessibilityPostNotification(_container, NSAccessibilityLayoutChangedNotification);
}

// The remote root's window is the container's, which changes as Refrax re-parents the page.
- (void)containerDidMoveToWindow {
  if (_accessibilityRoot) {
    _accessibilityRoot.windowUIElement = _container.window;
    _accessibilityRoot.topLevelUIElement = _container.window;
  }
}

- (void)accessibilityElementChanged {
  _accessibilityRoot = nil;
  if (_accessibilityStarted) {
    [self fetchAccessibilityRoot];
  }
}

// MARK: DevTools

- (void)showDevToolsWindowWithID:(uint64_t)viewID title:(NSString*)title {
  [self dismissDevToolsWindow];
  _devToolsContainer = [[RFXChromiumContainerView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 700)];
  _devToolsContainer.wantsLayer = YES;
  __weak RFXChromiumPage* weakSelf = self;
  _devToolsContainer.sizeDidChange = ^(NSSize size) {
    [weakSelf devToolsDidResize:size];
  };
  _devToolsWindow =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 700)
                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                            NSWindowStyleMaskResizable |
                                            NSWindowStyleMaskMiniaturizable
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  _devToolsWindow.releasedWhenClosed = NO;
  _devToolsWindow.title = title;
  _devToolsWindow.delegate = self;
  _devToolsWindow.contentView = _devToolsContainer;
  _devToolsWindow.frameAutosaveName = @"RFXChromiumDevTools";
  _devToolsViewIDMapping =
      std::make_unique<remote_cocoa::ScopedNSViewIdMapping>(viewID, _devToolsContainer);
  [self devToolsDidResize:_devToolsContainer.frame.size];
  if (![_devToolsWindow setFrameUsingName:@"RFXChromiumDevTools"]) {
    [_devToolsWindow center];
  }
  [_devToolsWindow makeKeyAndOrderFront:nil];
}

- (void)devToolsDidResize:(NSSize)size {
  if (!_closed && _devToolsContainer) {
    _page->SetDevToolsSize(gfx::Size(size.width, size.height));
  }
}

// The host has taken the frontend's views out of the window.
- (void)closeDevToolsWindow {
  [self dismissDevToolsWindow];
  _devToolsViewIDMapping.reset();
}

- (void)dismissDevToolsWindow {
  if (!_devToolsWindow) {
    return;
  }
  _devToolsWindow.delegate = nil;
  [_devToolsWindow close];
  _devToolsWindow = nil;
  _devToolsContainer.sizeDidChange = nil;
}

// A key the DevTools frontend left: ⌘W closes its window, as in any window; the rest go to
// Refrax's menus.
- (void)devToolsKeyDown:(NSEvent*)event {
  const NSEventModifierFlags flags =
      event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  if (flags == NSEventModifierFlagCommand &&
      [event.charactersIgnoringModifiers isEqualToString:@"w"]) {
    if (_devToolsWindow) {
      [self windowShouldClose:_devToolsWindow];
    }
    return;
  }
  [NSApp.mainMenu performKeyEquivalent:event];
}

- (BOOL)windowShouldClose:(NSWindow*)window {
  // The host takes the frontend's views out first, then asks for the window to close.
  [self performCommand:[@"{\"devTools\":{\"command\":{\"hide\":{}}}}"
                           dataUsingEncoding:NSUTF8StringEncoding]];
  return NO;
}

// MARK: Request log

- (void)requestLogSince:(int64_t)sequence completion:(void (^)(NSData* log))completion {
  NSData* (^empty)(void) = ^NSData* {
    return [[NSString stringWithFormat:@"{\"entries\":[],\"nextSequence\":%lld}",
                                       (long long)sequence + 1]
        dataUsingEncoding:NSUTF8StringEncoding];
  };
  if (_closed) {
    completion(empty());
    return;
  }
  _page->RequestLog(
      sequence,
      mojo::WrapCallbackWithDropHandler(
          base::BindOnce([](void (^completion)(NSData*),
                            const std::string& log) { completion(ToData(log)); },
                         completion),
          base::BindOnce([](void (^completion)(NSData*), NSData* (^empty)(void)) {
            completion(empty());
          }, completion, empty)));
}

- (NSView*)view {
  return _container;
}

- (void)attachToContainerID:(uint64_t)viewID {
  if (_closed || viewID == 0) {
    return;
  }
  // The host looks the container up by this id when it builds the page's views, and CHECKs
  // that it exists: register before asking.
  _viewIDMapping = std::make_unique<remote_cocoa::ScopedNSViewIdMapping>(viewID, _container);
  [self containerDidResize:_container.frame.size];
  _page->AttachView();
}

- (void)containerDidResize:(NSSize)size {
  if (!_closed) {
    _page->SetSize(gfx::Size(size.width, size.height));
  }
}

- (void)performCommand:(NSData*)command {
  if (!_closed) {
    _page->PerformCommand(ToString(command));
  }
}

- (void)evaluateScript:(NSData*)request
            completion:(void (^)(NSData* _Nullable, NSError* _Nullable))completion {
  if (_closed) {
    completion(nil, [NSError errorWithDomain:@"RFXChromiumEngine"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey : @"The page is closed."}]);
    return;
  }
  // Pending replies die with the page's remote when the page closes or the host exits;
  // Refrax awaits every completion, so a dropped one still completes, with an error.
  _page->EvaluateScript(
      ToString(request),
      mojo::WrapCallbackWithDropHandler(
          base::BindOnce(
              [](void (^completion)(NSData*, NSError*), const std::optional<std::string>& result,
                 const std::optional<std::string>& error) {
                if (result) {
                  completion(ToData(*result), nil);
                } else {
                  completion(nil, [NSError errorWithDomain:@"RFXChromiumEngine"
                                                      code:2
                                                  userInfo:@{
                                                    NSLocalizedDescriptionKey :
                                                        base::SysUTF8ToNSString(error.value_or(""))
                                                  }]);
                }
              },
              completion),
          base::BindOnce(
              [](void (^completion)(NSData*, NSError*)) { completion(nil, PageGoneError()); },
              completion)));
}

- (void)snapshotRect:(NSRect)rect
          completion:(void (^)(CGImageRef _Nullable, NSError* _Nullable))completion {
  if (_closed) {
    completion(nullptr, [NSError errorWithDomain:@"RFXChromiumEngine"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey : @"The page is closed."}]);
    return;
  }
  const gfx::Rect area = NSIsEmptyRect(rect) ? gfx::Rect() : gfx::ToEnclosingRect(gfx::RectF(rect));
  _page->Snapshot(
      area, mojo::WrapCallbackWithDropHandler(base::BindOnce(
                [](void (^completion)(CGImageRef, NSError*), const SkBitmap& bitmap) {
                  CGImageRef image = bitmap.isNull() ? nullptr : SkCreateCGImageRef(bitmap);
                  if (!image) {
                    completion(nullptr,
                               [NSError errorWithDomain:@"RFXChromiumEngine"
                                                   code:3
                                               userInfo:@{
                                                 NSLocalizedDescriptionKey :
                                                     @"The page has nothing rendered to capture."
                                               }]);
                    return;
                  }
                  completion(image, nil);
                  CGImageRelease(image);
                },
                completion),
                base::BindOnce(
                    [](void (^completion)(CGImageRef, NSError*)) {
                      completion(nullptr, PageGoneError());
                    },
                    completion)));
}

- (void)close {
  if (_closed) {
    return;
  }
  _closed = YES;
  _delegate = nil;
  _client.reset();
  _container.accessibilityRoot = nil;
  _accessibilityRoot = nil;
  [_container removeFromSuperview];
  [self dismissDevToolsWindow];
  if (!_page.is_bound()) {
    _viewIDMapping.reset();
    _devToolsViewIDMapping.reset();
    return;
  }
  // The host may still attach this page's views to the container, found by its id, until it
  // has closed the page; an id it can't find is a CHECK in this process. Its reply to Close
  // comes after every such message, so the id stays registered, and the connection open,
  // until then.
  auto closing = std::make_unique<ClosingPage>();
  closing->page = std::move(_page);
  closing->view_id_mapping = std::move(_viewIDMapping);
  closing->devtools_view_id_mapping = std::move(_devToolsViewIDMapping);
  closing->container = _container;
  closing->devtools_container = _devToolsContainer;
  refrax::mojom::Page* page = closing->page.get();
  page->Close(base::BindOnce([](std::unique_ptr<ClosingPage>) {}, std::move(closing)));
}

- (void)hostDidTerminate {
  _page.reset();
  _client.reset();
  _closed = YES;
  [self dismissDevToolsWindow];
  _devToolsViewIDMapping.reset();
}

@end
