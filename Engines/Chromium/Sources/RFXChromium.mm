// Chromium engine plug-in: CEF behind the Objective-C protocols in RFXChromium.h.
//
// Threading: CEF's UI thread is the process main thread. Every CEF call below
// and every CefClient callback that reaches the delegate runs on it. CEF's own
// message loop is driven from the app's run loop (external message pump), since
// multi_threaded_message_loop is unsupported on macOS and CefRunMessageLoop
// would take over [NSApp run].

#import "RFXChromium.h"

#include <map>
#include <string>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_parser.h"
#include "include/cef_request_context.h"
#include "include/cef_version.h"
#include "include/wrapper/cef_library_loader.h"

@class RFXChromiumBrowserImpl;

namespace {

NSString* const kErrorDomain = @"RFXChromiumErrorDomain";

// Upper bound between pump iterations while CEF has not asked for sooner work.
constexpr int64_t kMaxPumpDelayMs = 1000 / 30;

std::string ToStd(NSString* string) {
  return string ? std::string(string.UTF8String) : std::string();
}

NSString* ToNS(const CefString& string) {
  return [NSString stringWithUTF8String:string.ToString().c_str()] ?: @"";
}

NSURL* _Nullable ToURL(const CefString& string) {
  NSString* value = ToNS(string);
  return value.length ? [NSURL URLWithString:value] : nil;
}

NSError* MakeError(NSInteger code, NSString* message) {
  return [NSError errorWithDomain:kErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : message}];
}

}  // namespace

// MARK: - Message pump

/// Drives CefDoMessageLoopWork from the main run loop, following the
/// scheduling contract of CefBrowserProcessHandler::OnScheduleMessagePumpWork.
@interface RFXChromiumPump : NSObject
- (void)scheduleWorkAfter:(int64_t)delayMs;
- (void)invalidate;
@end

@implementation RFXChromiumPump {
  NSTimer* _timer;
  BOOL _isActive;
  BOOL _reentrancyDetected;
  BOOL _invalidated;
}

- (void)scheduleWorkAfter:(int64_t)delayMs {
  if (_invalidated) {
    return;
  }
  [_timer invalidate];
  _timer = nil;
  if (delayMs <= 0) {
    [self doWork];
    return;
  }
  NSTimeInterval interval = MIN(delayMs, kMaxPumpDelayMs) / 1000.0;
  _timer = [NSTimer timerWithTimeInterval:interval target:self selector:@selector(timerFired:) userInfo:nil repeats:NO];
  [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)timerFired:(NSTimer*)timer {
  _timer = nil;
  [self doWork];
}

- (void)doWork {
  if (_isActive) {
    _reentrancyDetected = YES;
    return;
  }
  _reentrancyDetected = NO;
  _isActive = YES;
  CefDoMessageLoopWork();
  _isActive = NO;
  if (_reentrancyDetected) {
    [self scheduleWorkAfter:0];
  } else if (!_timer) {
    [self scheduleWorkAfter:kMaxPumpDelayMs];
  }
}

- (void)invalidate {
  _invalidated = YES;
  [_timer invalidate];
  _timer = nil;
}

@end

// MARK: - Browser container view

/// Hosts the Chromium view. The CefBrowser is created the first time this view
/// joins a window, because Chromium's view needs a window for its screen and
/// scale-factor information.
@interface RFXChromiumContainerView : NSView
@property (nonatomic, weak) RFXChromiumBrowserImpl* owner;
@end

@interface RFXChromiumBrowserImpl : NSObject <RFXChromiumBrowser>
- (instancetype)initWithURL:(nullable NSURL*)url requestContext:(CefRefPtr<CefRequestContext>)context;
- (void)containerDidMoveToWindow:(nullable NSWindow*)window;
- (void)containerDidLayout;
@end

@interface RFXChromiumEngineImpl : NSObject <RFXChromiumEngine>
+ (nullable instancetype)current;
- (BOOL)isContextReady;
- (void)contextDidInitialize;
- (void)scheduleWorkAfter:(int64_t)delayMs;
- (void)browserDidClose:(RFXChromiumBrowserImpl*)browser;
@end

// MARK: - CEF client

namespace {

RFXChromiumOpenDisposition MapDisposition(cef_window_open_disposition_t disposition) {
  switch (disposition) {
    case CEF_WOD_CURRENT_TAB:
      return RFXChromiumOpenDispositionCurrentTab;
    case CEF_WOD_NEW_BACKGROUND_TAB:
      return RFXChromiumOpenDispositionBackgroundTab;
    case CEF_WOD_NEW_POPUP:
      return RFXChromiumOpenDispositionPopup;
    case CEF_WOD_NEW_WINDOW:
      return RFXChromiumOpenDispositionNewWindow;
    default:
      return RFXChromiumOpenDispositionForegroundTab;
  }
}

/// Forwards CEF callbacks to the Objective-C browser object. Holds it weakly:
/// the browser object owns the client, never the reverse.
class Client : public CefClient,
               public CefDisplayHandler,
               public CefLoadHandler,
               public CefLifeSpanHandler,
               public CefRequestHandler,
               public CefDownloadHandler,
               public CefDevToolsMessageObserver {
 public:
  explicit Client(RFXChromiumBrowserImpl* owner) : owner_(owner) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }

  // CefDisplayHandler
  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override;
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override;
  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString>& icon_urls) override;
  void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) override;
  void OnStatusMessage(CefRefPtr<CefBrowser> browser, const CefString& value) override;
  void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) override;

  // CefLoadHandler
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) override;
  void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition_type) override;
  void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int httpStatusCode) override;
  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override;

  // CefLifeSpanHandler
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString& target_url,
                     const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures& popupFeatures,
                     CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info,
                     bool* no_javascript_access) override;
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;

  // CefRequestHandler
  bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        const CefString& target_url,
                        WindowOpenDisposition target_disposition,
                        bool user_gesture) override;
  void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                 TerminationStatus status,
                                 int error_code,
                                 const CefString& error_string) override;

  // CefDownloadHandler
  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString& suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override;
  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefDownloadItem> download_item,
                         CefRefPtr<CefDownloadItemCallback> callback) override;

  // CefDevToolsMessageObserver
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,
                              int message_id,
                              bool success,
                              const void* result,
                              size_t result_size) override;

  void Detach() { owner_ = nil; }

 private:
  __weak RFXChromiumBrowserImpl* owner_;

  IMPLEMENT_REFCOUNTING(Client);
};

/// Browser-process hooks: command-line policy and the message pump schedule.
class App : public CefApp, public CefBrowserProcessHandler {
 public:
  explicit App(NSArray<NSString*>* switches) : switches_(switches) {}

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  void OnBeforeCommandLineProcessing(const CefString& process_type,
                                     CefRefPtr<CefCommandLine> command_line) override {
    if (!process_type.empty()) {
      return;
    }
    // Chromium's cookie encryption otherwise asks for the login keychain under
    // Chromium's own item name on first use.
    command_line->AppendSwitch("use-mock-keychain");
    // The media router's DIAL/mDNS discovery triggers the Local Network privacy prompt.
    command_line->AppendSwitchWithValue("disable-features", "MediaRouter,DialMediaRouteProvider");
    command_line->AppendSwitch("disable-component-update");
    for (NSString* entry in switches_) {
      NSRange separator = [entry rangeOfString:@"="];
      if (separator.location == NSNotFound) {
        command_line->AppendSwitch(ToStd(entry));
      } else {
        command_line->AppendSwitchWithValue(ToStd([entry substringToIndex:separator.location]),
                                            ToStd([entry substringFromIndex:NSMaxRange(separator)]));
      }
    }
  }

  void OnContextInitialized() override {
    [[RFXChromiumEngineImpl current] contextDidInitialize];
  }

  void OnScheduleMessagePumpWork(int64_t delay_ms) override {
    // Called from any thread.
    dispatch_async(dispatch_get_main_queue(), ^{
      [[RFXChromiumEngineImpl current] scheduleWorkAfter:delay_ms];
    });
  }

 private:
  NSArray<NSString*>* switches_;

  IMPLEMENT_REFCOUNTING(App);
};

}  // namespace

// MARK: - Browser

@interface RFXChromiumBrowserImpl ()
- (void)handleURL:(nullable NSURL*)url;
- (void)handleTitle:(NSString*)title;
- (void)handleLoading:(BOOL)isLoading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)handleDevToolsResult:(int)messageID success:(BOOL)success data:(NSData*)data;
- (void)handleBeforeClose;
@end

@implementation RFXChromiumContainerView

- (BOOL)isFlipped {
  return YES;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self.owner containerDidMoveToWindow:self.window];
}

- (void)layout {
  [super layout];
  [self.owner containerDidLayout];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
  [super resizeSubviewsWithOldSize:oldSize];
  [self.owner containerDidLayout];
}

@end

@implementation RFXChromiumBrowserImpl {
  RFXChromiumContainerView* _container;
  CefRefPtr<CefRequestContext> _requestContext;
  CefRefPtr<Client> _client;
  CefRefPtr<CefBrowser> _browser;
  CefRefPtr<CefRegistration> _devToolsRegistration;
  NSURL* _pendingURL;
  NSURL* _URL;
  NSString* _title;
  BOOL _isLoading;
  BOOL _canGoBack;
  BOOL _canGoForward;
  BOOL _hidden;
  BOOL _closed;
  double _zoomFactor;
  int _nextMessageID;
  NSMutableDictionary<NSNumber*, void (^)(id, NSError*)>* _pendingEvaluations;
}

@synthesize delegate = _delegate;

- (instancetype)initWithURL:(NSURL*)url requestContext:(CefRefPtr<CefRequestContext>)context {
  if ((self = [super init])) {
    _container = [[RFXChromiumContainerView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _container.owner = self;
    _container.wantsLayer = YES;
    _requestContext = context;
    _pendingURL = url;
    _URL = url;
    _title = @"";
    _zoomFactor = 1.0;
    _nextMessageID = 1;
    _pendingEvaluations = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSView*)view {
  return _container;
}

- (NSURL*)URL {
  return _URL;
}

- (NSString*)title {
  return _title;
}

- (BOOL)isLoading {
  return _isLoading;
}

- (BOOL)canGoBack {
  return _canGoBack;
}

- (BOOL)canGoForward {
  return _canGoForward;
}

- (double)zoomFactor {
  return _zoomFactor;
}

- (void)setZoomFactor:(double)zoomFactor {
  _zoomFactor = zoomFactor;
  if (_browser) {
    // Chromium zoom levels are logarithmic: factor = 1.2 ^ level.
    _browser->GetHost()->SetZoomLevel(log(zoomFactor) / log(1.2));
  }
}

// MARK: Lifecycle

- (void)containerDidMoveToWindow:(NSWindow*)window {
  if (_closed) {
    return;
  }
  if (window && !_browser) {
    [self createBrowserIfPossible];
  }
  if (_browser) {
    _browser->GetHost()->WasHidden(window == nil || _hidden);
  }
}

- (void)containerDidLayout {
  NSView* browserView = _container.subviews.firstObject;
  if (browserView && !NSEqualRects(browserView.frame, _container.bounds)) {
    browserView.frame = _container.bounds;
  }
}

- (void)createBrowserIfPossible {
  RFXChromiumEngineImpl* engine = [RFXChromiumEngineImpl current];
  if (_browser || _closed || !_container.window || !engine.isContextReady) {
    return;
  }
  NSRect bounds = _container.bounds;
  CefWindowInfo windowInfo;
  windowInfo.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(_container),
                        CefRect(0, 0, static_cast<int>(NSWidth(bounds)), static_cast<int>(NSHeight(bounds))));
  CefBrowserSettings settings;
  _client = new Client(self);
  NSString* initialURL = _pendingURL.absoluteString ?: @"about:blank";
  _pendingURL = nil;
  _browser = CefBrowserHost::CreateBrowserSync(windowInfo, _client, ToStd(initialURL), settings, nullptr,
                                               _requestContext);
  if (!_browser) {
    NSLog(@"[RFXChromium] CreateBrowserSync failed for %@", initialURL);
    return;
  }
  _devToolsRegistration = _browser->GetHost()->AddDevToolsMessageObserver(_client);
  if (_zoomFactor != 1.0) {
    self.zoomFactor = _zoomFactor;
  }
  [self containerDidLayout];
}

/// Retries creation for containers that joined a window before CEF's context was ready.
- (void)contextDidBecomeReady {
  if (_container.window) {
    [self createBrowserIfPossible];
  }
}

- (void)close {
  if (_closed) {
    return;
  }
  _closed = YES;
  _devToolsRegistration = nullptr;
  if (_browser) {
    _browser->GetHost()->CloseBrowser(true);
  } else {
    [self handleBeforeClose];
  }
  for (void (^completion)(id, NSError*) in _pendingEvaluations.allValues) {
    completion(nil, MakeError(3, @"The browser closed before the script finished."));
  }
  [_pendingEvaluations removeAllObjects];
}

- (void)handleBeforeClose {
  if (_client) {
    _client->Detach();
  }
  _browser = nullptr;
  _client = nullptr;
  [[RFXChromiumEngineImpl current] browserDidClose:self];
}

// MARK: Navigation

- (void)loadURL:(NSURL*)url {
  _URL = url;
  if (_browser) {
    _browser->GetMainFrame()->LoadURL(ToStd(url.absoluteString));
  } else {
    _pendingURL = url;
  }
}

- (void)goBack {
  if (_browser) {
    _browser->GoBack();
  }
}

- (void)goForward {
  if (_browser) {
    _browser->GoForward();
  }
}

- (void)reload {
  if (_browser) {
    _browser->Reload();
  }
}

- (void)reloadIgnoringCache {
  if (_browser) {
    _browser->ReloadIgnoreCache();
  }
}

- (void)stopLoading {
  if (_browser) {
    _browser->StopLoad();
  }
}

// MARK: Visibility and focus

- (void)setHidden:(BOOL)hidden {
  _hidden = hidden;
  if (_browser) {
    _browser->GetHost()->WasHidden(hidden || _container.window == nil);
  }
}

- (void)focus {
  if (_browser) {
    _browser->GetHost()->SetFocus(true);
  }
}

// MARK: Find and tools

- (void)findString:(NSString*)string forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
  if (_browser) {
    _browser->GetHost()->Find(ToStd(string), forward, matchCase, findNext);
  }
}

- (void)stopFinding {
  if (_browser) {
    _browser->GetHost()->StopFinding(true);
  }
}

- (void)showDevTools {
  if (_browser) {
    CefWindowInfo windowInfo;
    CefBrowserSettings settings;
    _browser->GetHost()->ShowDevTools(windowInfo, nullptr, settings, CefPoint());
  }
}

// MARK: JavaScript

- (void)evaluateJavaScript:(NSString*)script completionHandler:(void (^)(id, NSError*))completionHandler {
  if (!_browser) {
    completionHandler(nil, MakeError(1, @"The Chromium browser has not been created yet."));
    return;
  }
  CefRefPtr<CefDictionaryValue> params = CefDictionaryValue::Create();
  params->SetString("expression", ToStd(script));
  params->SetBool("returnByValue", true);
  params->SetBool("awaitPromise", true);
  int messageID = _nextMessageID++;
  _pendingEvaluations[@(messageID)] = [completionHandler copy];
  if (_browser->GetHost()->ExecuteDevToolsMethod(messageID, "Runtime.evaluate", params) == 0) {
    [_pendingEvaluations removeObjectForKey:@(messageID)];
    completionHandler(nil, MakeError(2, @"Runtime.evaluate could not be sent."));
  }
}

- (void)handleDevToolsResult:(int)messageID success:(BOOL)success data:(NSData*)data {
  void (^completion)(id, NSError*) = _pendingEvaluations[@(messageID)];
  if (!completion) {
    return;
  }
  [_pendingEvaluations removeObjectForKey:@(messageID)];
  NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (!success || ![json isKindOfClass:NSDictionary.class]) {
    completion(nil, MakeError(4, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"DevTools error"));
    return;
  }
  NSDictionary* exception = json[@"exceptionDetails"];
  if (exception) {
    NSString* message = exception[@"exception"][@"description"] ?: exception[@"text"] ?: @"JavaScript exception";
    completion(nil, MakeError(5, message));
    return;
  }
  id value = json[@"result"][@"value"];
  completion(value == NSNull.null ? nil : value, nil);
}

// MARK: Delegate relays

- (void)handleURL:(NSURL*)url {
  if (!url) {
    return;
  }
  _URL = url;
  [_delegate chromiumBrowser:self didChangeURL:url];
}

- (void)handleTitle:(NSString*)title {
  _title = [title copy];
  [_delegate chromiumBrowser:self didChangeTitle:_title];
}

- (void)handleLoading:(BOOL)isLoading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward {
  _isLoading = isLoading;
  _canGoBack = canGoBack;
  _canGoForward = canGoForward;
  [_delegate chromiumBrowser:self didChangeLoading:isLoading canGoBack:canGoBack canGoForward:canGoForward];
}

@end

// MARK: - Client implementation

namespace {

void Client::OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) {
  if (frame->IsMain()) {
    [owner_ handleURL:ToURL(url)];
  }
}

void Client::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
  [owner_ handleTitle:ToNS(title)];
}

void Client::OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString>& icon_urls) {
  NSMutableArray<NSURL*>* urls = [NSMutableArray array];
  for (const auto& icon : icon_urls) {
    if (NSURL* url = ToURL(icon)) {
      [urls addObject:url];
    }
  }
  RFXChromiumBrowserImpl* owner = owner_;
  [owner.delegate chromiumBrowser:owner didChangeFaviconURLs:urls];
}

void Client::OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) {
  RFXChromiumBrowserImpl* owner = owner_;
  [owner.delegate chromiumBrowser:owner didChangeFullscreen:fullscreen];
}

void Client::OnStatusMessage(CefRefPtr<CefBrowser> browser, const CefString& value) {
  RFXChromiumBrowserImpl* owner = owner_;
  [owner.delegate chromiumBrowser:owner didHoverLink:ToURL(value)];
}

void Client::OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) {
  RFXChromiumBrowserImpl* owner = owner_;
  [owner.delegate chromiumBrowser:owner didChangeProgress:progress];
}

void Client::OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) {
  [owner_ handleLoading:isLoading canGoBack:canGoBack canGoForward:canGoForward];
}

void Client::OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition_type) {
  if (!frame->IsMain()) {
    return;
  }
  // OnLoadStart fires after the navigation commits, which is the point at
  // which Refrax's history layer records a visit.
  bool isBackForward = (transition_type & TT_FORWARD_BACK_FLAG) != 0;
  RFXChromiumBrowserImpl* owner = owner_;
  [owner handleURL:ToURL(frame->GetURL())];
  [owner.delegate chromiumBrowser:owner didCommitNavigationBackForward:isBackForward];
}

void Client::OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int httpStatusCode) {
  if (!frame->IsMain()) {
    return;
  }
  RFXChromiumBrowserImpl* owner = owner_;
  [owner.delegate chromiumBrowser:owner didFinishLoadWithStatusCode:httpStatusCode];
}

void Client::OnLoadError(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefFrame> frame,
                         ErrorCode errorCode,
                         const CefString& errorText,
                         const CefString& failedUrl) {
  if (!frame->IsMain() || errorCode == ERR_ABORTED) {
    return;
  }
  RFXChromiumBrowserImpl* owner = owner_;
  [owner.delegate chromiumBrowser:owner
         didFailLoadWithErrorCode:errorCode
                      description:ToNS(errorText)
                        failedURL:ToURL(failedUrl)];
}

bool Client::OnBeforePopup(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefFrame> frame,
                           int popup_id,
                           const CefString& target_url,
                           const CefString& target_frame_name,
                           WindowOpenDisposition target_disposition,
                           bool user_gesture,
                           const CefPopupFeatures& popupFeatures,
                           CefWindowInfo& windowInfo,
                           CefRefPtr<CefClient>& client,
                           CefBrowserSettings& settings,
                           CefRefPtr<CefDictionaryValue>& extra_info,
                           bool* no_javascript_access) {
  // Refrax owns every window and tab, so popups become tab requests.
  if (NSURL* url = ToURL(target_url)) {
    RFXChromiumBrowserImpl* owner = owner_;
    [owner.delegate chromiumBrowser:owner
                 requestsOpeningURL:url
                        disposition:MapDisposition(target_disposition)
                        userGesture:user_gesture];
  }
  return true;
}

void Client::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  [owner_ handleBeforeClose];
}

bool Client::OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefFrame> frame,
                              const CefString& target_url,
                              WindowOpenDisposition target_disposition,
                              bool user_gesture) {
  // Cmd-click and middle-click land here with a new-tab disposition.
  if (target_disposition == CEF_WOD_CURRENT_TAB) {
    return false;
  }
  if (NSURL* url = ToURL(target_url)) {
    RFXChromiumBrowserImpl* owner = owner_;
    [owner.delegate chromiumBrowser:owner
                 requestsOpeningURL:url
                        disposition:MapDisposition(target_disposition)
                        userGesture:user_gesture];
  }
  return true;
}

void Client::OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                       TerminationStatus status,
                                       int error_code,
                                       const CefString& error_string) {
  RFXChromiumBrowserImpl* owner = owner_;
  [owner.delegate chromiumBrowser:owner renderProcessTerminatedWithStatus:status];
}

bool Client::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefDownloadItem> download_item,
                              const CefString& suggested_name,
                              CefRefPtr<CefBeforeDownloadCallback> callback) {
  RFXChromiumBrowserImpl* owner = owner_;
  NSURL* source = ToURL(download_item->GetURL());
  NSURL* destination = source ? [owner.delegate chromiumBrowser:owner
                                    destinationForDownloadOfURL:source
                                                  suggestedName:ToNS(suggested_name)]
                              : nil;
  if (!destination) {
    return false;
  }
  callback->Continue(ToStd(destination.path), false);
  return true;
}

void Client::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                               CefRefPtr<CefDownloadItem> download_item,
                               CefRefPtr<CefDownloadItemCallback> callback) {
  NSString* path = ToNS(download_item->GetFullPath());
  if (!path.length) {
    return;
  }
  RFXChromiumBrowserImpl* owner = owner_;
  [owner.delegate chromiumBrowser:owner
                downloadDidUpdate:[NSURL fileURLWithPath:path]
                    receivedBytes:download_item->GetReceivedBytes()
                       totalBytes:download_item->GetTotalBytes()
                       isComplete:download_item->IsComplete()
                       isCanceled:download_item->IsCanceled()];
}

void Client::OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,
                                    int message_id,
                                    bool success,
                                    const void* result,
                                    size_t result_size) {
  NSData* data = [NSData dataWithBytes:result length:result_size];
  [owner_ handleDevToolsResult:message_id success:success data:data];
}

}  // namespace

// MARK: - Engine

@implementation RFXChromiumEngineImpl {
  CefRefPtr<App> _app;
  RFXChromiumPump* _pump;
  BOOL _running;
  BOOL _contextReady;
  NSString* _rootCachePath;
  std::map<std::string, CefRefPtr<CefRequestContext>> _contexts;
  NSHashTable<RFXChromiumBrowserImpl*>* _waitingForContext;
  NSMutableSet<RFXChromiumBrowserImpl*>* _liveBrowsers;
}

static __weak RFXChromiumEngineImpl* g_current;

+ (instancetype)current {
  return g_current;
}

- (instancetype)init {
  if ((self = [super init])) {
    _waitingForContext = [NSHashTable weakObjectsHashTable];
    _liveBrowsers = [NSMutableSet set];
  }
  return self;
}

- (NSString*)version {
  return @CEF_VERSION;
}

- (BOOL)isRunning {
  return _running;
}

- (BOOL)isContextReady {
  return _contextReady;
}

- (BOOL)startWithConfiguration:(NSDictionary<RFXChromiumConfigurationKey, id>*)configuration error:(NSError**)error {
  NSAssert(NSThread.isMainThread, @"CEF must start on the main thread");
  if (_running) {
    return YES;
  }
  if (g_current && g_current != self) {
    if (error) *error = MakeError(10, @"Another Chromium engine instance is already running.");
    return NO;
  }
  NSString* frameworkPath = configuration[RFXChromiumConfigurationFrameworkPath];
  NSString* helperPath = configuration[RFXChromiumConfigurationHelperPath];
  _rootCachePath = configuration[RFXChromiumConfigurationRootCachePath];
  NSString* logPath = configuration[RFXChromiumConfigurationLogPath];
  if (!frameworkPath || !helperPath || !_rootCachePath) {
    if (error) *error = MakeError(11, @"frameworkPath, helperPath and rootCachePath are required.");
    return NO;
  }

  // Chromium creates its UI-thread message pump in CefInitialize and needs NSApp to report
  // whether -sendEvent: is on the stack. The host adopts the protocol at compile time.
  if (![NSApplication.sharedApplication conformsToProtocol:@protocol(CefAppProtocol)]) {
    if (error) *error = MakeError(14, @"The host application's NSApplication subclass must adopt CefAppProtocol.");
    return NO;
  }

  // Resolve every cef_* entry point from the framework before any CEF call.
  NSString* binary = [frameworkPath stringByAppendingPathComponent:@"Chromium Embedded Framework"];
  if (!cef_load_library(binary.fileSystemRepresentation)) {
    if (error) *error = MakeError(12, [NSString stringWithFormat:@"cef_load_library failed for %@", binary]);
    return NO;
  }


  g_current = self;
  _pump = [[RFXChromiumPump alloc] init];
  _app = new App(configuration[RFXChromiumConfigurationSwitches] ?: @[]);

  CefSettings settings;
  settings.no_sandbox = true;
  settings.external_message_pump = true;
  settings.multi_threaded_message_loop = false;
  settings.persist_session_cookies = true;
  settings.log_severity = LOGSEVERITY_WARNING;
  CefString(&settings.framework_dir_path) = ToStd(frameworkPath);
  CefString(&settings.browser_subprocess_path) = ToStd(helperPath);
  CefString(&settings.main_bundle_path) = ToStd(NSBundle.mainBundle.bundlePath);
  CefString(&settings.root_cache_path) = ToStd(_rootCachePath);
  CefString(&settings.cache_path) = ToStd([_rootCachePath stringByAppendingPathComponent:@"Default"]);
  if (logPath) {
    CefString(&settings.log_file) = ToStd(logPath);
  }

  // Chromium parses argv for switches; hand it only the executable so the
  // app's own launch arguments are never interpreted as Chromium switches.
  static char* argv0 = strdup(NSProcessInfo.processInfo.arguments.firstObject.fileSystemRepresentation);
  static char* argv[] = {argv0, nullptr};
  CefMainArgs mainArgs(1, argv);

  // Initialize. The context becomes usable in OnContextInitialized.
  if (!CefInitialize(mainArgs, settings, _app, nullptr)) {
    g_current = nil;
    if (error) *error = MakeError(13, [NSString stringWithFormat:@"CefInitialize failed (exit code %d)", CefGetExitCode()]);
    return NO;
  }
  _running = YES;
  [_pump scheduleWorkAfter:0];
  return YES;
}

- (void)contextDidInitialize {
  _contextReady = YES;
  for (RFXChromiumBrowserImpl* browser in _waitingForContext.allObjects) {
    [browser contextDidBecomeReady];
  }
  [_waitingForContext removeAllObjects];
}

- (void)scheduleWorkAfter:(int64_t)delayMs {
  [_pump scheduleWorkAfter:delayMs];
}

- (CefRefPtr<CefRequestContext>)requestContextForProfilePath:(NSString*)profilePath {
  std::string key = ToStd(profilePath);
  auto existing = _contexts.find(key);
  if (existing != _contexts.end()) {
    return existing->second;
  }
  CefRequestContextSettings settings;
  settings.persist_session_cookies = true;
  if (profilePath.length) {
    // Must be a child of root_cache_path.
    CefString(&settings.cache_path) = ToStd([_rootCachePath stringByAppendingPathComponent:profilePath]);
  }
  CefRefPtr<CefRequestContext> context = CefRequestContext::CreateContext(settings, nullptr);
  _contexts[key] = context;
  return context;
}

- (id<RFXChromiumBrowser>)makeBrowserWithURL:(NSURL*)url profilePath:(NSString*)profilePath {
  RFXChromiumBrowserImpl* browser =
      [[RFXChromiumBrowserImpl alloc] initWithURL:url requestContext:[self requestContextForProfilePath:profilePath]];
  [_liveBrowsers addObject:browser];
  if (!_contextReady) {
    [_waitingForContext addObject:browser];
  }
  return browser;
}

- (void)browserDidClose:(RFXChromiumBrowserImpl*)browser {
  [_liveBrowsers removeObject:browser];
}

- (void)shutdown {
  if (!_running) {
    return;
  }
  for (RFXChromiumBrowserImpl* browser in _liveBrowsers.allObjects) {
    [browser close];
  }
  // Let the close messages reach the renderers before tearing down.
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
  while (_liveBrowsers.count && deadline.timeIntervalSinceNow > 0) {
    CefDoMessageLoopWork();
    [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  [_pump invalidate];
  _contexts.clear();
  _running = NO;
  if (_liveBrowsers.count == 0) {
    CefShutdown();
  }
}

@end
