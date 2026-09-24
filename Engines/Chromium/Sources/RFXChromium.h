// Objective-C surface of the Chromium engine plug-in (RefraxChromium.dylib).
//
// The dylib is loaded at runtime with dlopen, so the app never links against it
// or against the Chromium Embedded Framework. Every type the app touches is a
// protocol: Swift reaches the implementation through NSClassFromString and
// talks to it only through these declarations. This header must stay free of
// C++ so the Swift bridging header can import it.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Host application contract

// Chromium's message pump needs to know whether -[NSApplication sendEvent:] is on
// the stack, so the host's NSApplication subclass must adopt these (Refrax:
// RefraxApplication). Same selectors and names as base/message_loop and
// include/cef_application_mac.h; the ObjC runtime unifies protocols by name.

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

// MARK: - Engine

@protocol RFXChromiumBrowser;

/// Keys for the configuration dictionary passed to `-[RFXChromiumEngine startWithConfiguration:error:]`.
typedef NSString *RFXChromiumConfigurationKey NS_TYPED_ENUM;
/// Absolute path to `Chromium Embedded Framework.framework`.
static RFXChromiumConfigurationKey const RFXChromiumConfigurationFrameworkPath = @"frameworkPath";
/// Absolute path to the base helper executable (`… Helper.app/Contents/MacOS/…`).
static RFXChromiumConfigurationKey const RFXChromiumConfigurationHelperPath = @"helperPath";
/// Absolute path to the directory holding every profile's on-disk state.
static RFXChromiumConfigurationKey const RFXChromiumConfigurationRootCachePath = @"rootCachePath";
/// Absolute path to the Chromium log file.
static RFXChromiumConfigurationKey const RFXChromiumConfigurationLogPath = @"logPath";
/// Optional `NSArray<NSString *>` of extra Chromium command-line switches (without leading dashes).
static RFXChromiumConfigurationKey const RFXChromiumConfigurationSwitches = @"switches";

/// How the page asked for a new browsing context to be shown.
typedef NS_ENUM(NSInteger, RFXChromiumOpenDisposition) {
    RFXChromiumOpenDispositionCurrentTab = 0,
    RFXChromiumOpenDispositionForegroundTab,
    RFXChromiumOpenDispositionBackgroundTab,
    RFXChromiumOpenDispositionPopup,
    RFXChromiumOpenDispositionNewWindow,
};

/// Events a browser reports back to its owner. Always delivered on the main thread.
@protocol RFXChromiumBrowserDelegate <NSObject>
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser didChangeURL:(NSURL *)url;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser didChangeTitle:(NSString *)title;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser
    didChangeLoading:(BOOL)isLoading
           canGoBack:(BOOL)canGoBack
        canGoForward:(BOOL)canGoForward;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser didChangeProgress:(double)progress;
/// A main-frame navigation committed. `isBackForward` is true for history traversals.
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser didCommitNavigationBackForward:(BOOL)isBackForward;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser didFinishLoadWithStatusCode:(NSInteger)statusCode;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser
    didFailLoadWithErrorCode:(NSInteger)errorCode
                 description:(NSString *)description
                   failedURL:(nullable NSURL *)failedURL;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser didChangeFaviconURLs:(NSArray<NSURL *> *)urls;
/// The URL under the pointer, or nil when the pointer leaves a link.
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser didHoverLink:(nullable NSURL *)url;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser
    requestsOpeningURL:(NSURL *)url
           disposition:(RFXChromiumOpenDisposition)disposition
           userGesture:(BOOL)userGesture;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser didChangeFullscreen:(BOOL)fullscreen;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser renderProcessTerminatedWithStatus:(NSInteger)status;
/// Returns where a download should be written, or nil to cancel it.
- (nullable NSURL *)chromiumBrowser:(id<RFXChromiumBrowser>)browser
    destinationForDownloadOfURL:(NSURL *)url
                  suggestedName:(NSString *)suggestedName;
- (void)chromiumBrowser:(id<RFXChromiumBrowser>)browser
    downloadDidUpdate:(NSURL *)destination
        receivedBytes:(int64_t)receivedBytes
           totalBytes:(int64_t)totalBytes
           isComplete:(BOOL)isComplete
           isCanceled:(BOOL)isCanceled;
@end

/// One Chromium browsing context (a CefBrowser) and the view that displays it.
@protocol RFXChromiumBrowser <NSObject>
/// The container view. The Chromium view is created inside it once it joins a window.
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<RFXChromiumBrowserDelegate> delegate;
@property (nonatomic, readonly, nullable) NSURL *URL;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
/// Page zoom as a multiplier (1.0 = 100%).
@property (nonatomic) double zoomFactor;

- (void)loadURL:(NSURL *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)reloadIgnoringCache;
- (void)stopLoading;
/// Evaluates `script` in the main frame through the DevTools protocol and returns its JSON value.
- (void)evaluateJavaScript:(NSString *)script
         completionHandler:(void (^)(id _Nullable result, NSError *_Nullable error))completionHandler;
- (void)setHidden:(BOOL)hidden;
- (void)focus;
- (void)findString:(NSString *)string forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext;
- (void)stopFinding;
- (void)showDevTools;
/// Closes the browser. The object stays valid but inert afterwards.
- (void)close;
@end

/// The process-wide Chromium runtime. Exactly one instance exists per process.
@protocol RFXChromiumEngine <NSObject>
/// CEF version string, e.g. "154.0.23+g062ebe4+chromium-154.0.8037.17".
@property (nonatomic, readonly, copy) NSString *version;
@property (nonatomic, readonly) BOOL isRunning;

/// Loads the framework and calls CefInitialize. NSApp must already adopt `CefAppProtocol`.
- (BOOL)startWithConfiguration:(NSDictionary<RFXChromiumConfigurationKey, id> *)configuration
                         error:(NSError *_Nullable *_Nullable)error;

/// Creates a browser that loads `url` once its view joins a window.
///
/// Browsers sharing a `profilePath` share cookies and storage; nil gives an in-memory profile.
- (id<RFXChromiumBrowser>)makeBrowserWithURL:(nullable NSURL *)url profilePath:(nullable NSString *)profilePath;

/// Closes every browser and shuts CEF down. Call once, from applicationWillTerminate.
- (void)shutdown;
@end

NS_ASSUME_NONNULL_END
