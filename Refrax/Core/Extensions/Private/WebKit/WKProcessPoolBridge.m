@import WebKit;
#import "WKProcessPoolPrivate.h"
#import "WKProcessPoolBridge.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation WKProcessPoolBridge

+ (NSArray<_WKProcessInfo *> *)webContentProcessInfo {
    return [WKProcessPool _webContentProcessInfo];
}

+ (nullable _WKProcessInfo *)gpuProcessInfo {
    return [WKProcessPool _gpuProcessInfo];
}

@end

#pragma clang diagnostic pop
