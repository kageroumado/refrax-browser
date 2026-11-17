// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import "RFXRemoteEngine.h"

#import "RFXRemotePage.h"
#import "RFXRemotePageView.h"
#import "RFXRemoteWire.h"

#import <spawn.h>
#import <sys/socket.h>
#import <sys/wait.h>

NSString *const RFXRemoteHostExecutableKey = @"RFXRemoteHostExecutable";

static NSString *const RFXRemoteEngineErrorDomain = @"website.refrax.engine.remote";

extern char **environ;

static NSError *RFXRemoteError(NSString *message) {
    return [NSError errorWithDomain:RFXRemoteEngineErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// How long a host may take to start before the engine counts as failed.
static const NSTimeInterval RFXRemoteStartTimeout = 45;
/// How long a host gets to exit after `shutdown` before it is killed.
static const NSTimeInterval RFXRemoteShutdownGrace = 5;

@implementation RFXRemoteEngine {
    RFXRemoteWire *_wire;
    pid_t _hostPID;
    dispatch_source_t _hostExitSource;
    NSMapTable<NSNumber *, RFXRemotePage *> *_pages;
    NSMutableDictionary<NSNumber *, void (^)(void)> *_profileRemovals;
    void (^_startCompletion)(NSError *_Nullable);
    NSString *_terminationReason;
    uint64_t _nextPageNumber;
    uint64_t _nextRequestID;
    BOOL _terminated;
    BOOL _shutDown;
}

@synthesize delegate = _delegate;

- (instancetype)init {
    if ((self = [super init])) {
        _pages = [NSMapTable strongToWeakObjectsMapTable];
        _profileRemovals = [NSMutableDictionary dictionary];
        _nextPageNumber = 1;
        _nextRequestID = 1;
    }
    return self;
}

- (uint64_t)nextRequestID {
    return _nextRequestID++;
}

- (void)send:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields {
    [_wire send:name fields:fields];
}

// MARK: Starting the host

- (nullable NSString *)hostExecutablePath {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *relative = [bundle objectForInfoDictionaryKey:RFXRemoteHostExecutableKey];
    if (![relative isKindOfClass:[NSString class]] || relative.length == 0) {
        return nil;
    }
    NSString *path = [[bundle.bundlePath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:relative];
    return [NSFileManager.defaultManager isExecutableFileAtPath:path] ? path : nil;
}

/// Starts the host with one end of a socket pair as its only inherited descriptor besides its
/// log, and returns the other end.
- (int)spawnHost:(NSString *)path logPath:(nullable NSString *)logPath error:(NSError **)error {
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0) {
        *error = RFXRemoteError(@"The engine's socket could not be made");
        return -1;
    }
    // Room for a burst either way without either side waiting on the other.
    int bufferSize = 4 * 1024 * 1024;
    for (int index = 0; index < 2; index++) {
        setsockopt(sockets[index], SOL_SOCKET, SO_SNDBUF, &bufferSize, sizeof(bufferSize));
        setsockopt(sockets[index], SOL_SOCKET, SO_RCVBUF, &bufferSize, sizeof(bufferSize));
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    const char *log = logPath ? logPath.fileSystemRepresentation : "/dev/null";
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log, O_WRONLY | O_CREAT | O_APPEND, 0600);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    posix_spawn_file_actions_addinherit_np(&actions, sockets[1]);

    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    // Nothing of Refrax's reaches the host but the descriptors named above.
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT);

    NSString *wireArgument = [NSString stringWithFormat:@"--wire-fd=%d", sockets[1]];
    char *const arguments[] = {(char *)path.fileSystemRepresentation, (char *)wireArgument.UTF8String, NULL};
    pid_t pid = 0;
    int status = posix_spawn(&pid, path.fileSystemRepresentation, &actions, &attributes, arguments, environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    close(sockets[1]);

    if (status != 0) {
        close(sockets[0]);
        *error = RFXRemoteError([NSString stringWithFormat:@"The engine host did not start: %s", strerror(status)]);
        return -1;
    }

    _hostPID = pid;
    // The host leaves the process table once it has been waited for.
    _hostExitSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
    dispatch_source_t exitSource = _hostExitSource;
    dispatch_source_set_event_handler(exitSource, ^{
        int exitStatus = 0;
        waitpid(pid, &exitStatus, WNOHANG);
        dispatch_source_cancel(exitSource);
    });
    dispatch_resume(exitSource);
    return sockets[0];
}

- (void)startWithConfiguration:(NSData *)configuration completion:(void (^)(NSError *_Nullable))completion {
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:configuration options:0 error:NULL];
    NSURL *storage = [parsed isKindOfClass:[NSDictionary class]] && [parsed[@"storageDirectory"] isKindOfClass:[NSString class]]
        ? [NSURL URLWithString:parsed[@"storageDirectory"]]
        : nil;
    if (!storage.isFileURL || _wire) {
        completion(RFXRemoteError(_wire ? @"The engine has started already" : @"The configuration names no storage directory"));
        return;
    }
    NSString *hostPath = [self hostExecutablePath];
    if (!hostPath) {
        completion(RFXRemoteError(@"The engine bundle has no host executable"));
        return;
    }
    [NSFileManager.defaultManager createDirectoryAtURL:storage withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *logFile = [parsed[@"logFile"] isKindOfClass:[NSString class]] ? [NSURL URLWithString:parsed[@"logFile"]] : nil;

    NSError *error = nil;
    int descriptor = [self spawnHost:hostPath logPath:logFile.isFileURL ? logFile.path : nil error:&error];
    if (descriptor < 0) {
        completion(error);
        return;
    }

    _startCompletion = [completion copy];
    _wire = [[RFXRemoteWire alloc] initWithFileDescriptor:descriptor];
    __weak RFXRemoteEngine *weakSelf = self;
    _wire.onMessage = ^(NSString *name, NSDictionary<NSString *, id> *fields) {
        [weakSelf handleMessage:name fields:fields];
    };
    _wire.onClose = ^{
        [weakSelf hostDidTerminate];
    };

    NSArray *languages = [parsed[@"languages"] isKindOfClass:[NSArray class]] ? parsed[@"languages"] : @[];
    [self send:@"start" fields:@{@"storagePath": storage.path, @"languages": languages}];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RFXRemoteStartTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf finishStartingWithError:RFXRemoteError(@"The engine host did not start in time")];
    });
}

- (void)finishStartingWithError:(nullable NSError *)error {
    void (^completion)(NSError *_Nullable) = _startCompletion;
    if (!completion) {
        return;
    }
    _startCompletion = nil;
    completion(error);
}

// MARK: Messages from the host

- (void)handleMessage:(NSString *)name fields:(NSDictionary<NSString *, id> *)fields {
    if ([name isEqualToString:@"started"]) {
        [self finishStartingWithError:nil];
    } else if ([name isEqualToString:@"startFailed"]) {
        NSString *message = [fields[@"message"] isKindOfClass:[NSString class]] ? fields[@"message"] : @"The engine host failed to start";
        [self finishStartingWithError:RFXRemoteError(message)];
    } else if ([name isEqualToString:@"terminated"]) {
        _terminationReason = [fields[@"reason"] isKindOfClass:[NSString class]] ? fields[@"reason"] : nil;
    } else if ([name isEqualToString:@"profileRemoved"]) {
        NSNumber *identifier = [fields[@"id"] isKindOfClass:[NSNumber class]] ? fields[@"id"] : nil;
        void (^completion)(void) = identifier ? _profileRemovals[identifier] : nil;
        if (completion) {
            _profileRemovals[identifier] = nil;
            completion();
        }
    } else if ([name isEqualToString:@"clipboardWrite"]) {
        if ([fields[@"text"] isKindOfClass:[NSString class]]) {
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:fields[@"text"] forType:NSPasteboardTypeString];
        }
    } else if ([name isEqualToString:@"clipboardRead"]) {
        NSString *text = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] ?: @"";
        if (fields[@"id"] && fields[@"profile"]) {
            [self send:@"clipboardText" fields:@{@"id": fields[@"id"], @"profile": fields[@"profile"], @"text": text}];
        }
    } else if ([name isEqualToString:@"engineEvent"]) {
        NSData *event = fields[@"event"] ? [NSJSONSerialization dataWithJSONObject:fields[@"event"] options:0 error:NULL] : nil;
        id<RFXEngineHostDelegate> delegate = self.delegate;
        if (event && [delegate respondsToSelector:@selector(engineHost:didEmitEvent:)]) {
            [delegate engineHost:self didEmitEvent:event];
        }
    } else {
        NSNumber *number = [fields[@"page"] isKindOfClass:[NSNumber class]] ? fields[@"page"] : nil;
        RFXRemotePage *page = number ? [_pages objectForKey:number] : nil;
        [page handleMessage:name fields:fields];
    }
}

- (void)hostDidTerminate {
    if (_terminated) {
        return;
    }
    _terminated = YES;
    [_wire close];
    NSString *reason = _terminationReason ?: @"The engine host exited";
    [self finishStartingWithError:RFXRemoteError(reason)];

    for (RFXRemotePage *page in _pages.objectEnumerator.allObjects) {
        [page hostDidTerminate];
    }
    NSDictionary<NSNumber *, void (^)(void)> *removals = [_profileRemovals copy];
    [_profileRemovals removeAllObjects];
    for (void (^completion)(void) in removals.objectEnumerator) {
        completion();
    }
    if (!_shutDown) {
        [self.delegate engineHostDidTerminateWithReason:reason];
    }
}

// MARK: RFXEngineHost

- (nullable id<RFXEnginePage>)makePageWithSpec:(NSData *)spec error:(NSError **)error {
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:spec options:0 error:NULL];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = RFXRemoteError(@"The page spec is not a JSON object");
        }
        return nil;
    }
    if (!_wire || _terminated || _shutDown) {
        if (error) {
            *error = RFXRemoteError(@"The engine is not running");
        }
        return nil;
    }

    RFXRemotePage *page = [[RFXRemotePage alloc] initWithEngine:self number:_nextPageNumber++];
    [_pages setObject:page forKey:@(page.number)];

    NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithDictionary:[(RFXRemotePageView *)page.view geometry]];
    fields[@"page"] = @(page.number);
    fields[@"spec"] = parsed;
    fields[@"framesPerSecond"] = @(NSScreen.mainScreen.maximumFramesPerSecond ?: 60);
    [self send:@"makePage" fields:fields];
    return page;
}

- (void)pageDidClose:(RFXRemotePage *)page {
    [_pages removeObjectForKey:@(page.number)];
}

- (void)applyPolicy:(NSData *)update {
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:update options:0 error:NULL];
    if ([parsed isKindOfClass:[NSDictionary class]]) {
        [self send:@"policy" fields:@{@"update": parsed}];
    }
}

- (void)performCommand:(NSData *)command {
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:command options:0 error:NULL];
    if ([parsed isKindOfClass:[NSDictionary class]]) {
        [self send:@"engineCommand" fields:@{@"command": parsed}];
    }
}

- (void)removeProfile:(NSData *)profile completion:(void (^)(void))completion {
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:profile options:0 error:NULL];
    if (![parsed isKindOfClass:[NSDictionary class]] || !_wire || _terminated || _shutDown) {
        completion();
        return;
    }
    NSNumber *identifier = @([self nextRequestID]);
    _profileRemovals[identifier] = [completion copy];
    [self send:@"removeProfile" fields:@{@"id": identifier, @"profile": parsed}];
}

- (void)shutdown {
    if (_shutDown) {
        return;
    }
    _shutDown = YES;
    for (RFXRemotePage *page in _pages.objectEnumerator.allObjects) {
        [page close];
    }
    if (_terminated || !_wire) {
        return;
    }
    [self send:@"shutdown" fields:@{}];

    // A host that is stuck never reads the message.
    pid_t pid = _hostPID;
    dispatch_source_t exitSource = _hostExitSource;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RFXRemoteShutdownGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (dispatch_source_testcancel(exitSource) == 0) {
            kill(pid, SIGKILL);
        }
    });
}

@end
