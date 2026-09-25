// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_CLIENT_CHROMIUM_PAGE_H_
#define REFRAX_CLIENT_CHROMIUM_PAGE_H_

#import <AppKit/AppKit.h>

#include "mojo/public/cpp/bindings/pending_associated_receiver.h"
#include "mojo/public/cpp/bindings/pending_associated_remote.h"
#include "refrax/common/mojom/engine.mojom.h"
#import "refrax/sdk/RFXEngine.h"

// One page of the Chromium engine. Its view is a container the host fills with Chromium's own
// WebContents and RenderWidgetHost views (remote_cocoa); everything else crosses the contract
// as JSON, passed through untouched.
@interface RFXChromiumPage : NSObject <RFXEnginePage>

- (instancetype)initWithPage:(mojo::PendingAssociatedRemote<refrax::mojom::Page>)page
                      client:(mojo::PendingAssociatedReceiver<refrax::mojom::PageClient>)client
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The host created the page: register the container under `viewID` and let the host build
// the page's views in it. 0 means the host could not create the page.
- (void)attachToContainerID:(uint64_t)viewID;

// The engine host went away.
- (void)hostDidTerminate;

@end

#endif  // REFRAX_CLIENT_CHROMIUM_PAGE_H_
