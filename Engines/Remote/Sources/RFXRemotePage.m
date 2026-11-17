// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import "RFXRemotePage.h"

#import "RFXRemoteEngine.h"
#import "RFXRemotePageView.h"

static NSError *RFXRemotePageError(NSString *message) {
    return [NSError errorWithDomain:@"website.refrax.engine.remote" code:2 userInfo:@{NSLocalizedDescriptionKey: message}];
}

typedef void (^RFXEvaluationCompletion)(NSData *_Nullable result, NSError *_Nullable error);
typedef void (^RFXSnapshotCompletion)(CGImageRef _Nullable image, NSError *_Nullable error);

@implementation RFXRemotePage {
    __weak RFXRemoteEngine *_engine;
    RFXRemotePageView *_view;
    NSMutableDictionary<NSNumber *, RFXEvaluationCompletion> *_evaluations;
    NSMutableDictionary<NSNumber *, RFXSnapshotCompletion> *_snapshots;
    NSMutableDictionary<NSNumber *, NSValue *> *_snapshotRects;
    BOOL _hostGone;
}

@synthesize delegate = _delegate;

- (instancetype)initWithEngine:(RFXRemoteEngine *)engine number:(uint64_t)number {
    if ((self = [super init])) {
        _engine = engine;
        _number = number;
        _evaluations = [NSMutableDictionary dictionary];
        _snapshots = [NSMutableDictionary dictionary];
        _snapshotRects = [NSMutableDictionary dictionary];
        _view = [[RFXRemotePageView alloc] initWithPage:self];
    }
    return self;
}

- (NSView *)view {
    return _view;
}

- (uint64_t)nextRequestID {
    return [_engine nextRequestID];
}

- (void)send:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields {
    if (_closed || _hostGone) {
        return;
    }
    NSMutableDictionary *message = [NSMutableDictionary dictionaryWithDictionary:fields];
    message[@"page"] = @(_number);
    [_engine send:name fields:message];
}

// MARK: RFXEnginePage

- (void)performCommand:(NSData *)command {
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:command options:0 error:NULL];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        return;
    }
    // Keystrokes reach the page through its view, so focus is the view's as well as the page's.
    if (parsed[@"focus"]) {
        [_view.window makeFirstResponder:_view];
    }
    [self send:@"command" fields:@{@"command": parsed}];
}

- (void)evaluateScript:(NSData *)request completion:(RFXEvaluationCompletion)completion {
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:request options:0 error:NULL];
    if (_closed || _hostGone || ![parsed isKindOfClass:[NSDictionary class]]) {
        NSString *reason = _closed ? @"The page is closed" : _hostGone ? @"The engine is gone" : @"The script request is not a JSON object";
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, RFXRemotePageError(reason));
        });
        return;
    }
    NSNumber *identifier = @([self nextRequestID]);
    _evaluations[identifier] = [completion copy];
    [self send:@"evaluate" fields:@{@"id": identifier, @"request": parsed}];
}

- (void)snapshotRect:(NSRect)rect completion:(RFXSnapshotCompletion)completion {
    if (_closed || _hostGone) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NULL, RFXRemotePageError(@"The page is closed"));
        });
        return;
    }
    NSNumber *identifier = @([self nextRequestID]);
    _snapshots[identifier] = [completion copy];
    _snapshotRects[identifier] = [NSValue valueWithRect:rect];
    [self send:@"snapshot" fields:@{@"id": identifier}];
}

- (void)close {
    if (_closed) {
        return;
    }
    [self send:@"closePage" fields:@{}];
    _closed = YES;
    [_view detachFromPage];
    [self failPendingCalls:@"The page was closed"];
    [_engine pageDidClose:self];
}

- (void)hostDidTerminate {
    if (_hostGone) {
        return;
    }
    _hostGone = YES;
    [self failPendingCalls:@"The engine is gone"];
    if (_closed) {
        return;
    }
    NSDictionary *event = @{@"rendererHealthChanged": @{@"health": @{@"terminated": @{@"reason": @"sharedProcessCrashed"}}}};
    [self.delegate enginePage:self didEmitEvent:[NSJSONSerialization dataWithJSONObject:event options:0 error:NULL]];
}

/// Every call Refrax awaits completes, whatever became of the page.
- (void)failPendingCalls:(NSString *)reason {
    NSDictionary<NSNumber *, RFXEvaluationCompletion> *evaluations = [_evaluations copy];
    [_evaluations removeAllObjects];
    NSDictionary<NSNumber *, RFXSnapshotCompletion> *snapshots = [_snapshots copy];
    [_snapshots removeAllObjects];
    [_snapshotRects removeAllObjects];
    if (evaluations.count == 0 && snapshots.count == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        for (RFXEvaluationCompletion completion in evaluations.objectEnumerator) {
            completion(nil, RFXRemotePageError(reason));
        }
        for (RFXSnapshotCompletion completion in snapshots.objectEnumerator) {
            completion(NULL, RFXRemotePageError(reason));
        }
    });
}

// MARK: Messages from the host

- (void)handleMessage:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields {
    if (_closed) {
        return;
    }
    NSNumber *identifier = [fields[@"id"] isKindOfClass:[NSNumber class]] ? fields[@"id"] : nil;

    if ([name isEqualToString:@"event"]) {
        NSData *event = [fields[@"event"] isKindOfClass:[NSDictionary class]] ? [NSJSONSerialization dataWithJSONObject:fields[@"event"] options:0 error:NULL] : nil;
        if (event) {
            [self.delegate enginePage:self didEmitEvent:event];
        }
    } else if ([name isEqualToString:@"request"]) {
        NSData *request = [fields[@"request"] isKindOfClass:[NSDictionary class]] ? [NSJSONSerialization dataWithJSONObject:fields[@"request"] options:0 error:NULL] : nil;
        if (!request || !identifier) {
            return;
        }
        __weak RFXRemotePage *weakSelf = self;
        __block BOOL answered = NO;
        [self.delegate enginePage:self didRequest:request reply:^(NSData *answer) {
            NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:answer options:0 error:NULL];
            if (answered || ![parsed isKindOfClass:[NSDictionary class]]) {
                return;
            }
            answered = YES;
            [weakSelf send:@"answer" fields:@{@"id": identifier, @"answer": parsed}];
        }];
    } else if ([name isEqualToString:@"scriptMessage"]) {
        NSData *message = [fields[@"message"] isKindOfClass:[NSDictionary class]] ? [NSJSONSerialization dataWithJSONObject:fields[@"message"] options:0 error:NULL] : nil;
        if (!message || !identifier) {
            return;
        }
        __weak RFXRemotePage *weakSelf = self;
        __block BOOL replied = NO;
        [self.delegate enginePage:self didReceiveScriptMessage:message reply:^(NSData *reply) {
            NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:reply options:0 error:NULL];
            if (replied || ![parsed isKindOfClass:[NSDictionary class]]) {
                return;
            }
            replied = YES;
            [weakSelf send:@"scriptReply" fields:@{@"id": identifier, @"reply": parsed}];
        }];
    } else if ([name isEqualToString:@"evaluated"]) {
        RFXEvaluationCompletion completion = identifier ? _evaluations[identifier] : nil;
        if (!completion) {
            return;
        }
        _evaluations[identifier] = nil;
        if ([fields[@"result"] isKindOfClass:[NSString class]]) {
            completion([(NSString *)fields[@"result"] dataUsingEncoding:NSUTF8StringEncoding], nil);
        } else {
            NSString *message = [fields[@"error"] isKindOfClass:[NSString class]] ? fields[@"error"] : @"The script failed";
            completion(nil, RFXRemotePageError(message));
        }
    } else if ([name isEqualToString:@"snapshotTaken"]) {
        RFXSnapshotCompletion completion = identifier ? _snapshots[identifier] : nil;
        if (!completion) {
            return;
        }
        NSRect rect = _snapshotRects[identifier].rectValue;
        _snapshots[identifier] = nil;
        _snapshotRects[identifier] = nil;
        CGImageRef image = [self newImageFromSnapshot:fields rect:rect];
        completion(image, image ? nil : RFXRemotePageError(@"The page has no frame to show"));
        CGImageRelease(image);
    } else if ([name isEqualToString:@"layer"]) {
        _view.remoteContextID = [fields[@"contextID"] isKindOfClass:[NSNumber class]] ? [fields[@"contextID"] unsignedIntValue] : 0;
    } else if ([name isEqualToString:@"cursor"]) {
        if ([fields[@"name"] isKindOfClass:[NSString class]]) {
            [_view setCursorNamed:fields[@"name"]];
        }
    } else if ([name isEqualToString:@"keyUnhandled"]) {
        if (identifier) {
            [_view keyWasUnhandled:identifier.unsignedLongLongValue];
        }
    } else if ([name isEqualToString:@"keyHandled"]) {
        if (identifier) {
            [_view keyWasHandled:identifier.unsignedLongLongValue];
        }
    } else if ([name isEqualToString:@"pageFailed"]) {
        NSDictionary *event = @{@"rendererHealthChanged": @{@"health": @{@"terminated": @{@"reason": @"unknown"}}}};
        [self.delegate enginePage:self didEmitEvent:[NSJSONSerialization dataWithJSONObject:event options:0 error:NULL]];
    }
}

/// The frame the host wrote to the file it names: BGRA with premultiplied alpha, top row first.
/// `rect` is in the view's points; an empty one takes the whole frame.
- (nullable CGImageRef)newImageFromSnapshot:(NSDictionary<NSString *, id> *)fields rect:(NSRect)rect CF_RETURNS_RETAINED {
    NSString *path = [fields[@"path"] isKindOfClass:[NSString class]] ? fields[@"path"] : nil;
    size_t width = [fields[@"width"] isKindOfClass:[NSNumber class]] ? [fields[@"width"] unsignedIntegerValue] : 0;
    size_t height = [fields[@"height"] isKindOfClass:[NSNumber class]] ? [fields[@"height"] unsignedIntegerValue] : 0;
    size_t bytesPerRow = [fields[@"bytesPerRow"] isKindOfClass:[NSNumber class]] ? [fields[@"bytesPerRow"] unsignedIntegerValue] : 0;
    if (!path || width == 0 || height == 0 || bytesPerRow < width * 4) {
        return NULL;
    }
    NSData *pixels = [NSData dataWithContentsOfFile:path];
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    if (pixels.length < bytesPerRow * height) {
        return NULL;
    }

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGBitmapInfo info = (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
    CGImageRef image = CGImageCreate(width, height, 8, 32, bytesPerRow, colorSpace, info, provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (!image || NSIsEmptyRect(rect) || NSIsEmptyRect(_view.bounds)) {
        return image;
    }

    CGFloat scaleX = (CGFloat)width / NSWidth(_view.bounds);
    CGFloat scaleY = (CGFloat)height / NSHeight(_view.bounds);
    CGRect crop = CGRectIntegral(CGRectMake(NSMinX(rect) * scaleX, NSMinY(rect) * scaleY, NSWidth(rect) * scaleX, NSHeight(rect) * scaleY));
    CGImageRef cropped = CGImageCreateWithImageInRect(image, crop);
    CGImageRelease(image);
    return cropped;
}

@end
