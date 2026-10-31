#import "WKContentBlockingPrivate.h"

WKUserScript *RFXMatchPatternUserScript(NSString *source,
                                        BOOL forMainFrameOnly,
                                        NSArray<NSString *> *includes,
                                        NSArray<NSString *> *excludes,
                                        WKContentWorld *world)
{
    return [[WKUserScript alloc] _initWithSource:source
                                   injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                forMainFrameOnly:forMainFrameOnly
                      includeMatchPatternStrings:includes
                      excludeMatchPatternStrings:excludes
                                   associatedURL:nil
                                    contentWorld:world];
}
