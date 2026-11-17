// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import "RFXRemoteWire.h"

#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <unistd.h>

/// The largest message either side sends. A frame claiming more is a broken stream.
static const NSUInteger RFXRemoteWireMaximumMessageSize = 64 * 1024 * 1024;

@implementation RFXRemoteWire {
    int _fileDescriptor;
    dispatch_source_t _readSource;
    NSMutableData *_received;
}

- (instancetype)initWithFileDescriptor:(int)fileDescriptor {
    if ((self = [super init])) {
        _fileDescriptor = fileDescriptor;
        _received = [NSMutableData data];
        fcntl(fileDescriptor, F_SETFL, fcntl(fileDescriptor, F_GETFL) | O_NONBLOCK);
        fcntl(fileDescriptor, F_SETFD, FD_CLOEXEC);

        _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fileDescriptor, 0, dispatch_get_main_queue());
        __weak RFXRemoteWire *weakSelf = self;
        dispatch_source_set_event_handler(_readSource, ^{
            [weakSelf readAvailable];
        });
        // The descriptor closes only once the source is done with it.
        dispatch_source_set_cancel_handler(_readSource, ^{
            close(fileDescriptor);
        });
        dispatch_resume(_readSource);
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (_fileDescriptor < 0) {
        return;
    }
    _fileDescriptor = -1;
    dispatch_source_cancel(_readSource);
}

- (void)closeFromPeer {
    if (_fileDescriptor < 0) {
        return;
    }
    [self close];
    void (^onClose)(void) = self.onClose;
    self.onClose = nil;
    if (onClose) {
        onClose();
    }
}

- (BOOL)writeAll:(const uint8_t *)bytes length:(NSUInteger)length {
    while (length > 0) {
        ssize_t written = write(_fileDescriptor, bytes, length);
        if (written > 0) {
            bytes += written;
            length -= (NSUInteger)written;
            continue;
        }
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written < 0 && errno == EAGAIN) {
            // The host reads as soon as its loop comes around.
            struct pollfd descriptor = {.fd = _fileDescriptor, .events = POLLOUT};
            poll(&descriptor, 1, 5000);
            if (descriptor.revents & POLLOUT) {
                continue;
            }
        }
        return NO;
    }
    return YES;
}

- (void)send:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields {
    if (_fileDescriptor < 0) {
        return;
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{name: fields} options:0 error:NULL];
    if (!body || body.length > RFXRemoteWireMaximumMessageSize) {
        return;
    }
    uint8_t header[4] = {
        (uint8_t)(body.length >> 24), (uint8_t)(body.length >> 16), (uint8_t)(body.length >> 8), (uint8_t)body.length,
    };
    if (![self writeAll:header length:sizeof(header)] || ![self writeAll:body.bytes length:body.length]) {
        [self closeFromPeer];
    }
}

- (void)readAvailable {
    for (;;) {
        uint8_t chunk[64 * 1024];
        ssize_t count = read(_fileDescriptor, chunk, sizeof(chunk));
        if (count > 0) {
            [_received appendBytes:chunk length:(NSUInteger)count];
            continue;
        }
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count < 0 && errno == EAGAIN) {
            break;
        }
        // Deliver what arrived before the end, then report it.
        [self dispatchMessages];
        [self closeFromPeer];
        return;
    }
    [self dispatchMessages];
}

- (void)dispatchMessages {
    // Every whole message leaves the buffer before any is handled: a handler can run a nested
    // run loop, which reads again.
    NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
    NSUInteger offset = 0;
    while (_received.length - offset >= 4) {
        const uint8_t *header = (const uint8_t *)_received.bytes + offset;
        NSUInteger length = ((NSUInteger)header[0] << 24) | ((NSUInteger)header[1] << 16) | ((NSUInteger)header[2] << 8) | header[3];
        if (length > RFXRemoteWireMaximumMessageSize) {
            [_received setLength:0];
            [self closeFromPeer];
            return;
        }
        if (_received.length - offset - 4 < length) {
            break;
        }
        NSData *body = [_received subdataWithRange:NSMakeRange(offset + 4, length)];
        offset += 4 + length;
        id message = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
        if ([message isKindOfClass:[NSDictionary class]]) {
            [messages addObject:message];
        }
    }
    if (offset > 0) {
        [_received replaceBytesInRange:NSMakeRange(0, offset) withBytes:NULL length:0];
    }

    for (NSDictionary *message in messages) {
        void (^onMessage)(NSString *, NSDictionary *) = self.onMessage;
        [message enumerateKeysAndObjectsUsingBlock:^(id name, id fields, BOOL *stop) {
            if (onMessage && [name isKindOfClass:[NSString class]] && [fields isKindOfClass:[NSDictionary class]]) {
                onMessage(name, fields);
            }
        }];
    }
}

@end
