@import WebKit;

@class _WKProcessInfo;

/// Bridges WKProcessPool's static process info methods without triggering
/// the WKProcessPool deprecation warning. The class is deprecated for
/// creating instances, but these static methods have no replacement.
NS_HEADER_AUDIT_BEGIN(nullability, sendability)

@interface WKProcessPoolBridge : NSObject
+ (NSArray<_WKProcessInfo *> *)webContentProcessInfo;
+ (nullable _WKProcessInfo *)gpuProcessInfo;
@end

NS_HEADER_AUDIT_END(nullability, sendability)
