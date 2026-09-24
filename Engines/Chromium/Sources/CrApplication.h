// Chromium's application protocols, which an in-process Chromium needs NSApp to
// adopt: its main-thread message pump asks whether -[NSApplication sendEvent:]
// is on the stack. Same selectors and names as base/message_loop and CEF's
// include/cef_application_mac.h; the ObjC runtime unifies protocols by name.
//
// Only the in-process CEF engine needs this. An out-of-process engine runs
// Chromium's message loop in its own process.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@protocol CrAppProtocol
/// Whether -[NSApplication sendEvent:] is currently on the stack.
- (BOOL)isHandlingSendEvent;
@end

NS_SWIFT_UI_ACTOR
@protocol CrAppControlProtocol <CrAppProtocol>
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent;
@end

NS_SWIFT_UI_ACTOR
@protocol CefAppProtocol <CrAppControlProtocol>
@end

NS_ASSUME_NONNULL_END
