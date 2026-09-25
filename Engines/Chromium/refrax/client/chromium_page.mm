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
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/utils/mac/SkCGUtils.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/size.h"

@class RFXChromiumPage;

namespace {

NSData* ToData(const std::string& string) {
  return [NSData dataWithBytes:string.data() length:string.size()];
}

std::string ToString(NSData* data) {
  return std::string(static_cast<const char*>(data.bytes), data.length);
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
// its size, since the host lays the page out.
@interface RFXChromiumContainerView : NSView
@property(nonatomic, copy) void (^sizeDidChange)(NSSize size);
@end

@implementation RFXChromiumContainerView

@synthesize sizeDidChange = _sizeDidChange;

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

@implementation RFXChromiumPage {
  mojo::AssociatedRemote<refrax::mojom::Page> _page;
  std::unique_ptr<PageClientImpl> _client;
  std::unique_ptr<remote_cocoa::ScopedNSViewIdMapping> _viewIDMapping;
  RFXChromiumContainerView* _container;
  BOOL _closed;
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
  }
  return self;
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
  _page->EvaluateScript(
      ToString(request),
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
          completion));
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
      area, base::BindOnce(
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
                completion));
}

- (void)close {
  if (_closed) {
    return;
  }
  _closed = YES;
  _delegate = nil;
  _page->Close();
  _page.reset();
  _client.reset();
  _viewIDMapping.reset();
  [_container removeFromSuperview];
}

- (void)hostDidTerminate {
  _page.reset();
  _client.reset();
  _closed = YES;
}

@end
