#import "RefraxExceptionCatch.h"

NSException *RefraxCatchingNSException(NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
