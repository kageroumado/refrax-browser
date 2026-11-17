// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import <AppKit/AppKit.h>

#import "../../SDK/RFXEngine.h"

NS_ASSUME_NONNULL_BEGIN

@class RFXRemoteEngine;

/// One page of an out-of-process engine: its view, and the calls the host answers.
@interface RFXRemotePage : NSObject <RFXEnginePage>

- (instancetype)initWithEngine:(RFXRemoteEngine *)engine number:(uint64_t)number NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// The engine's number for the page, which every message about it carries.
@property (nonatomic, readonly) uint64_t number;
@property (nonatomic, readonly, getter=isClosed) BOOL closed;

/// A message from the host about this page.
- (void)handleMessage:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields;
/// The host is gone: every pending call completes with an error.
- (void)hostDidTerminate;

- (void)send:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields;
- (uint64_t)nextRequestID;

@end

NS_ASSUME_NONNULL_END
