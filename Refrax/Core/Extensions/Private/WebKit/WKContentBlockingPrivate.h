/**
 * WKContentBlockingPrivate.h
 * Refrax Browser
 *
 * Private WebKit APIs Shields uses on WebKit: user scripts with match patterns, and the
 * per-load report of what a content rule list did.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUserScriptPrivate.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKContentRuleListAction.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegatePrivate.h
 */

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WKUserScript (WKPrivate)

/**
 * A user script limited to frames whose URL matches `includeMatchPatternStrings` (WebExtension
 * match patterns: scheme, host with an optional leading wildcard label, path) and none of
 * `excludeMatchPatternStrings`.
 */
- (instancetype)_initWithSource:(NSString *)source
                  injectionTime:(WKUserScriptInjectionTime)injectionTime
               forMainFrameOnly:(BOOL)forMainFrameOnly
     includeMatchPatternStrings:(nullable NSArray<NSString *> *)includeMatchPatternStrings
     excludeMatchPatternStrings:(nullable NSArray<NSString *> *)excludeMatchPatternStrings
                  associatedURL:(nullable NSURL *)associatedURL
                   contentWorld:(nullable WKContentWorld *)contentWorld
    API_AVAILABLE(macos(15.4));

@end

/**
 * A document-start user script for the frames `includes` and not `excludes` select, in
 * `world`. Wraps `-_initWithSource:…`, which Swift cannot call on an allocated instance.
 */
WKUserScript *RFXMatchPatternUserScript(NSString *source,
                                        BOOL forMainFrameOnly,
                                        NSArray<NSString *> *includes,
                                        NSArray<NSString *> *excludes,
                                        WKContentWorld *world)
    NS_SWIFT_NAME(makeMatchPatternUserScript(source:forMainFrameOnly:includes:excludes:world:));

@interface WKUserContentController (WKShieldsPrivate)

/** Removes one user script; the others stay in the web processes as they are. */
- (void)_removeUserScript:(WKUserScript *)userScript API_AVAILABLE(macos(10.12));

@end

/**
 * What a content rule list did to one load. Delivered to the navigation delegate's
 * `-_webView:contentRuleListWithIdentifier:performedAction:forURL:`.
 */
@interface _WKContentRuleListAction : NSObject

@property (nonatomic, readonly) BOOL blockedLoad;
@property (nonatomic, readonly) BOOL blockedCookies;
@property (nonatomic, readonly) BOOL madeHTTPS;
@property (nonatomic, readonly) BOOL redirected API_AVAILABLE(macos(13.0));
@property (nonatomic, readonly) BOOL modifiedHeaders API_AVAILABLE(macos(13.0));
@property (nonatomic, readonly, copy) NSArray<NSString *> *notifications;

@end

NS_ASSUME_NONNULL_END
