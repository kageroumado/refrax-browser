#import "RefraxExceptionRecorder.h"

#import <fcntl.h>
#import <objc/objc-exception.h>
#import <os/lock.h>
#import <pthread.h>
#import <unistd.h>

/// Records kept in the file; the newest is last.
static const NSUInteger kRecordCapacity = 4;
/// Longest reason kept per record, in UTF-16 units.
static const NSUInteger kReasonLimit = 2000;
/// Frames kept per record.
static const NSUInteger kFrameLimit = 64;
/// Throws per second that get a symbolicated stack. Beyond this, a record
/// carries raw return addresses, which cost no dladdr lookups.
static const NSUInteger kSymbolicatedPerSecond = 8;
/// Throws per second that get recorded at all, so code that throws in a loop
/// keeps its cost bounded.
static const NSUInteger kRecordedPerSecond = 64;

static objc_exception_preprocessor previousPreprocessor;
static os_unfair_lock recorderLock = OS_UNFAIR_LOCK_INIT;
static int fileDescriptor = -1;
static NSMutableArray<NSString *> *records;
static CFAbsoluteTime windowStart;
static NSUInteger windowCount;
static NSISO8601DateFormatter *timestampFormatter;
static NSRegularExpression *urlExpression;
static _Thread_local BOOL isRecording;

static NSString *RefraxThreadDescription(void) {
    if (NSThread.isMainThread) {
        return @"main thread";
    }
    NSString *name = NSThread.currentThread.name;
    if (name.length > 0) {
        return name;
    }
    char label[128] = {0};
    pthread_getname_np(pthread_self(), label, sizeof(label));
    return label[0] != 0 ? @(label) : @"unnamed thread";
}

/// Cuts every URL in an exception reason down to its scheme and host. The log
/// leaves the machine with crash reports, and reasons quote page URLs, paths,
/// and queries.
static NSString *RefraxRedactedReason(NSString *reason) {
    NSMutableString *redacted = [reason mutableCopy];
    NSArray<NSTextCheckingResult *> *matches = [urlExpression matchesInString:reason options:0 range:NSMakeRange(0, reason.length)];
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSString *scheme = [reason substringWithRange:[match rangeAtIndex:1]];
        NSRange hostRange = [match rangeAtIndex:2];
        NSString *host = hostRange.location != NSNotFound ? [reason substringWithRange:hostRange] : @"";
        [redacted replaceCharactersInRange:match.range withString:[NSString stringWithFormat:@"%@://%@/…", scheme, host]];
    }
    return redacted;
}

static NSString *RefraxStackDescription(NSException *exception, BOOL symbolicate) {
    NSArray<NSString *> *symbols = nil;
    if (symbolicate) {
        symbols = exception.callStackReturnAddresses.count > 0 ? exception.callStackSymbols : NSThread.callStackSymbols;
    }
    if (symbols.count > 0) {
        NSUInteger count = MIN(symbols.count, kFrameLimit);
        return [[symbols subarrayWithRange:NSMakeRange(0, count)] componentsJoinedByString:@"\n"];
    }
    NSArray<NSNumber *> *addresses = exception.callStackReturnAddresses;
    NSMutableString *stack = [NSMutableString string];
    NSUInteger count = MIN(addresses.count, kFrameLimit);
    for (NSUInteger index = 0; index < count; index++) {
        [stack appendFormat:@"%-3lu 0x%016lx\n", (unsigned long)index, addresses[index].unsignedLongValue];
    }
    return stack;
}

static void RefraxRecord(NSException *exception) {
    os_unfair_lock_lock(&recorderLock);

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - windowStart >= 1) {
        windowStart = now;
        windowCount = 0;
    }
    windowCount += 1;
    if (windowCount > kRecordedPerSecond) {
        os_unfair_lock_unlock(&recorderLock);
        return;
    }
    BOOL symbolicate = windowCount <= kSymbolicatedPerSecond;
    os_unfair_lock_unlock(&recorderLock);

    NSString *reason = RefraxRedactedReason(exception.reason ?: @"(no reason)");
    if (reason.length > kReasonLimit) {
        reason = [[reason substringToIndex:kReasonLimit] stringByAppendingString:@"…"];
    }
    NSString *record = [NSString stringWithFormat:@"[%@] %@\n%@: %@\n%@\n",
                        [timestampFormatter stringFromDate:[NSDate date]],
                        RefraxThreadDescription(),
                        exception.name,
                        reason,
                        RefraxStackDescription(exception, symbolicate)];

    os_unfair_lock_lock(&recorderLock);
    [records addObject:record];
    if (records.count > kRecordCapacity) {
        [records removeObjectAtIndex:0];
    }
    NSData *contents = [[records componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (pwrite(fileDescriptor, contents.bytes, contents.length, 0) >= 0) {
        ftruncate(fileDescriptor, (off_t)contents.length);
    }
    os_unfair_lock_unlock(&recorderLock);
}

static id RefraxExceptionPreprocessor(id exception) {
    id processed = previousPreprocessor != NULL ? previousPreprocessor(exception) : exception;
    if (!isRecording && [processed isKindOfClass:[NSException class]]) {
        isRecording = YES;
        @try {
            RefraxRecord(processed);
        } @catch (__unused id nested) {
        }
        isRecording = NO;
    }
    return processed;
}

void RefraxExceptionRecorderInstall(NSString *path) {
    int descriptor = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (descriptor < 0) {
        return;
    }

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        records = [NSMutableArray arrayWithCapacity:kRecordCapacity + 1];
        timestampFormatter = [[NSISO8601DateFormatter alloc] init];
        timestampFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        urlExpression = [NSRegularExpression regularExpressionWithPattern:@"\\b([a-zA-Z][a-zA-Z0-9+.-]*)://(?:[^/\\s'\"<>)@]*@)?([^/\\s'\"<>)]*)[^\\s'\"<>)]*" options:0 error:NULL];
    });

    os_unfair_lock_lock(&recorderLock);
    int replaced = fileDescriptor;
    fileDescriptor = descriptor;
    [records removeAllObjects];
    if (replaced >= 0) {
        close(replaced);
    } else {
        previousPreprocessor = objc_setExceptionPreprocessor(RefraxExceptionPreprocessor);
    }
    os_unfair_lock_unlock(&recorderLock);
}
