// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.
//
// The client's connection to an engine host: a socket carrying JSON objects, each after its
// length as four bytes, most significant first (Engines/Remote/PROTOCOL.md).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RFXRemoteWire : NSObject

/// Takes ownership of `fileDescriptor`. Messages and the close arrive on the main queue.
- (instancetype)initWithFileDescriptor:(int)fileDescriptor NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, copy, nullable) void (^onMessage)(NSString *name, NSDictionary<NSString *, id> *fields);
/// Called once, when the host's end closes or the stream breaks. Never called after `close`.
@property (nonatomic, copy, nullable) void (^onClose)(void);

- (void)send:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields;
- (void)close;

@end

NS_ASSUME_NONNULL_END
