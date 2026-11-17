// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.
//
// The engine-neutral client of an out-of-process engine: the principal class of an `.engine`
// bundle whose engine runs in a host process of its own. The client starts the host named by
// the bundle's Info.plist, passes the contract's JSON between it and Refrax over a socket
// (Engines/Remote/PROTOCOL.md), shows each page through the remote layer the host names, and
// forwards input. It holds nothing of any engine.

#import <AppKit/AppKit.h>

#import "../../SDK/RFXEngine.h"

NS_ASSUME_NONNULL_BEGIN

/// Info.plist key: the host executable, relative to the bundle's `Contents` directory.
extern NSString *const RFXRemoteHostExecutableKey;

@class RFXRemotePage;

@interface RFXRemoteEngine : NSObject <RFXEngineHost>

/// Sends one message to the host.
- (void)send:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields;
/// A number no other request of this engine has, for a message the host answers.
- (uint64_t)nextRequestID;
- (void)pageDidClose:(RFXRemotePage *)page;

@end

NS_ASSUME_NONNULL_END
