// Chromium (CEF) engine bundle: RFXEngine.h over the Chromium Embedded Framework.
//
// Runs in Refrax's process: the interim engine until an out-of-process Chromium
// host replaces it. It speaks the same contract that host will, so Refrax's
// side does not change.
//
// Threading: CEF's UI thread is the process main thread. Every CEF call below
// and every callback that reaches the delegate runs on it. CEF's message loop
// is driven from the app's run loop (external message pump), since
// multi_threaded_message_loop is unsupported on macOS and CefRunMessageLoop
// would take over [NSApp run].

#import "../../SDK/RFXEngine.h"
#import "CrApplication.h"

#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_set>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_parser.h"
#include "include/cef_request_context.h"
#include "include/cef_resource_request_handler.h"
#include "include/cef_ssl_status.h"
#include "include/cef_version.h"
#include "include/wrapper/cef_library_loader.h"

@class RFXChromiumPage;
@class RFXChromiumEngineHost;

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

NSError* MakeError(NSInteger code, NSString* message) {
  return [NSError errorWithDomain:kErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : message}];
}

// MARK: JSON

/// Contract messages are JSON objects with a single key naming the case.
NSData* Message(NSString* name, NSDictionary* fields) {
  return [NSJSONSerialization dataWithJSONObject:@{name : fields ?: @{}} options:0 error:nil];
}

NSDictionary* _Nullable ParseObject(NSData* data) {
  id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

/// Splits `{"caseName": {fields}}` into its name and fields.
BOOL ParseCase(NSData* data, NSString* _Nullable* name, NSDictionary* _Nullable* fields) {
  NSDictionary* object = ParseObject(data);
  if (object.count != 1) {
    return NO;
  }
  *name = object.allKeys.firstObject;
  id value = object[*name];
  *fields = [value isKindOfClass:NSDictionary.class] ? value : @{};
  return YES;
}

id JSONString(const CefString& string) {
  NSString* value = ToNS(string);
  return value.length ? value : NSNull.null;
}

NSString* _Nullable FilePath(id urlString) {
  return [urlString isKindOfClass:NSString.class] ? [NSURL URLWithString:urlString].path : nil;
}

NSString* FailureKind(int code) {
  switch (code) {
    case -3:  // ERR_ABORTED
      return @"cancelled";
    case -105:  // ERR_NAME_NOT_RESOLVED
    case -137:  // ERR_NAME_RESOLUTION_FAILED
      return @"cannotFindHost";
    case -102:  // ERR_CONNECTION_REFUSED
    case -109:  // ERR_ADDRESS_UNREACHABLE
      return @"cannotConnectToHost";
    case -106:  // ERR_INTERNET_DISCONNECTED
      return @"notConnectedToInternet";
    case -100:  // ERR_CONNECTION_CLOSED
    case -101:  // ERR_CONNECTION_RESET
      return @"connectionLost";
    case -7:    // ERR_TIMED_OUT
    case -118:  // ERR_CONNECTION_TIMED_OUT
      return @"timedOut";
    case -20:  // ERR_BLOCKED_BY_CLIENT
    case -27:  // ERR_BLOCKED_BY_RESPONSE
      return @"blockedByPolicy";
    default:
      return (code <= -200 && code > -300) ? @"certificateInvalid" : @"other";
  }
}

NSString* DispositionName(cef_window_open_disposition_t disposition) {
  switch (disposition) {
    case CEF_WOD_CURRENT_TAB:
      return @"currentTab";
    case CEF_WOD_NEW_BACKGROUND_TAB:
      return @"backgroundTab";
    case CEF_WOD_NEW_POPUP:
      return @"popup";
    case CEF_WOD_NEW_WINDOW:
      return @"newWindow";
    default:
      return @"foregroundTab";
  }
}

// MARK: Content blocking

/// The network rules this engine enforces from Refrax's filter lists: hosts from
/// `||host^` rules (and `@@||host^` exceptions) with no options, or only
/// `third-party`. That covers most of EasyList's network rules with an O(depth)
/// lookup; cosmetic and pattern rules are not applied by this engine.
struct BlockRules {
  std::unordered_set<std::string> blocked;
  std::unordered_set<std::string> exceptions;
};

std::mutex g_rulesMutex;
std::shared_ptr<const BlockRules> g_rules;

std::shared_ptr<const BlockRules> CurrentRules() {
  std::lock_guard<std::mutex> lock(g_rulesMutex);
  return g_rules;
}

void SetRules(std::shared_ptr<const BlockRules> rules) {
  std::lock_guard<std::mutex> lock(g_rulesMutex);
  g_rules = std::move(rules);
}

/// The host of a `||host^[$options]` rule, or empty when the rule is anything else.
std::string HostOfDomainRule(NSString* rule) {
  if (![rule hasPrefix:@"||"]) {
    return {};
  }
  NSRange caret = [rule rangeOfString:@"^"];
  if (caret.location == NSNotFound) {
    return {};
  }
  NSString* options = [rule substringFromIndex:NSMaxRange(caret)];
  if (options.length && ![options isEqualToString:@"$third-party"] && ![options isEqualToString:@"$3p"]) {
    return {};
  }
  NSString* host = [rule substringWithRange:NSMakeRange(2, caret.location - 2)].lowercaseString;
  NSCharacterSet* invalid =
      [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789.-"] invertedSet];
  if (!host.length || [host rangeOfCharacterFromSet:invalid].location != NSNotFound) {
    return {};
  }
  return ToStd(host);
}

std::shared_ptr<const BlockRules> ParseRules(NSArray<NSString*>* lists) {
  auto rules = std::make_shared<BlockRules>();
  for (NSString* contents in lists) {
    [contents enumerateLinesUsingBlock:^(NSString* line, BOOL*) {
      NSString* rule = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      BOOL isException = [rule hasPrefix:@"@@"];
      std::string host = HostOfDomainRule(isException ? [rule substringFromIndex:2] : rule);
      if (!host.empty()) {
        (isException ? rules->exceptions : rules->blocked).insert(host);
      }
    }];
  }
  return rules;
}

/// Whether `host` or any parent domain is blocked and not excepted.
bool IsBlocked(const BlockRules& rules, std::string host) {
  bool blocked = false;
  while (!host.empty()) {
    if (rules.exceptions.count(host)) {
      return false;
    }
    blocked = blocked || rules.blocked.count(host);
    size_t dot = host.find('.');
    host = dot == std::string::npos ? std::string() : host.substr(dot + 1);
  }
  return blocked;
}

/// Cancels subresource requests to blocked hosts. Called on CEF's IO thread.
class Blocker : public CefResourceRequestHandler {
 public:
  ReturnValue OnBeforeResourceLoad(CefRefPtr<CefBrowser>,
                                   CefRefPtr<CefFrame>,
                                   CefRefPtr<CefRequest> request,
                                   CefRefPtr<CefCallback>) override {
    if (request->GetResourceType() == RT_MAIN_FRAME) {
      return RV_CONTINUE;
    }
    std::shared_ptr<const BlockRules> rules = CurrentRules();
    CefURLParts parts;
    if (!rules || !CefParseURL(request->GetURL(), parts)) {
      return RV_CONTINUE;
    }
    std::string host = CefString(&parts.host).ToString();
    for (char& character : host) {
      character = static_cast<char>(tolower(character));
    }
    return IsBlocked(*rules, host) ? RV_CANCEL : RV_CONTINUE;
  }

 private:
  IMPLEMENT_REFCOUNTING(Blocker);
};

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

// MARK: - Declarations

/// Hosts the Chromium view. The CefBrowser is created the first time this view
/// joins a window, because Chromium's view needs a window for its screen and
/// scale-factor information.
@interface RFXChromiumContainerView : NSView
@property (nonatomic, weak) RFXChromiumPage* owner;
@end

@interface RFXChromiumPage : NSObject <RFXEnginePage>
- (instancetype)initWithURL:(nullable NSString*)url requestContext:(CefRefPtr<CefRequestContext>)context;
- (void)containerDidMoveToWindow:(nullable NSWindow*)window;
- (void)containerDidLayout;
- (void)contextDidBecomeReady;
- (void)emit:(NSString*)name fields:(nullable NSDictionary*)fields;
- (void)request:(NSString*)name fields:(NSDictionary*)fields reply:(void (^)(NSString* name, NSDictionary* fields))reply;
- (void)handleDevToolsResult:(int)messageID success:(BOOL)success data:(NSData*)data;
- (void)handleDevToolsEvent:(NSString*)method params:(NSData*)params;
- (void)installScripts:(NSArray<NSDictionary*>*)scripts;
- (void)handleBeforeClose;
/// The main frame's last committed URL.
@property(nonatomic, readonly, nullable) NSString* lastCommittedURL;
- (void)handleCommitWithURL:(NSString*)url isBackForward:(BOOL)isBackForward;
- (void)handleFinishWithURL:(NSString*)url statusCode:(int)statusCode;
@end

@interface RFXChromiumEngineHost : NSObject <RFXEngineHost>
+ (nullable instancetype)current;
- (BOOL)isContextReady;
- (void)contextDidInitialize;
- (void)scheduleWorkAfter:(int64_t)delayMs;
- (void)pageDidClose:(RFXChromiumPage*)page;
/// The scripts from the latest `scripts` policy (Engines/CONTRACT.md §4.5).
@property (nonatomic, readonly, copy) NSArray<NSDictionary*>* scripts;
@end

// MARK: - CEF client

namespace {

/// Translates CEF callbacks into contract events on the owning page. Holds the
/// page weakly: the page owns the client, never the reverse.
class Client : public CefClient,
               public CefDisplayHandler,
               public CefLoadHandler,
               public CefLifeSpanHandler,
               public CefRequestHandler,
               public CefDownloadHandler,
               public CefJSDialogHandler,
               public CefPermissionHandler,
               public CefDevToolsMessageObserver {
 public:
  explicit Client(RFXChromiumPage* owner) : owner_(owner) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }

  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(CefRefPtr<CefBrowser>,
                                                                 CefRefPtr<CefFrame>,
                                                                 CefRefPtr<CefRequest>,
                                                                 bool,
                                                                 bool,
                                                                 const CefString&,
                                                                 bool&) override {
    return blocker_;
  }

  void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (frame->IsMain()) {
      [owner_ emit:@"urlChanged" fields:@{@"url" : JSONString(url)}];
    }
  }

  void OnTitleChange(CefRefPtr<CefBrowser>, const CefString& title) override {
    [owner_ emit:@"titleChanged" fields:@{@"title" : ToNS(title)}];
  }

  void OnFaviconURLChange(CefRefPtr<CefBrowser>, const std::vector<CefString>& icon_urls) override {
    NSMutableArray* urls = [NSMutableArray array];
    for (const auto& icon : icon_urls) {
      [urls addObject:ToNS(icon)];
    }
    [owner_ emit:@"faviconsChanged" fields:@{@"urls" : urls}];
  }

  void OnFullscreenModeChange(CefRefPtr<CefBrowser>, bool fullscreen) override {
    [owner_ emit:@"fullscreenChanged" fields:@{@"state" : fullscreen ? @"active" : @"none"}];
  }

  void OnStatusMessage(CefRefPtr<CefBrowser>, const CefString& value) override {
    [owner_ emit:@"hoveredLinkChanged" fields:@{@"url" : JSONString(value)}];
  }

  void OnLoadingProgressChange(CefRefPtr<CefBrowser>, double progress) override {
    [owner_ emit:@"progressChanged" fields:@{@"progress" : @(progress)}];
  }

  void OnLoadingStateChange(CefRefPtr<CefBrowser>, bool isLoading, bool canGoBack, bool canGoForward) override {
    [owner_ emit:@"loadingChanged" fields:@{@"isLoading" : @(isLoading)}];
    [owner_ emit:@"backForwardChanged" fields:@{@"canGoBack" : @(canGoBack), @"canGoForward" : @(canGoForward)}];
  }

  // OnLoadStart fires once the main-frame navigation has committed.
  void OnLoadStart(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, TransitionType transition_type) override {
    if (frame->IsMain()) {
      [owner_ handleCommitWithURL:ToNS(frame->GetURL()) isBackForward:(transition_type & TT_FORWARD_BACK_FLAG) != 0];
    }
  }

  void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int httpStatusCode) override {
    if (!frame->IsMain()) {
      return;
    }
    [owner_ handleFinishWithURL:ToNS(frame->GetURL()) statusCode:httpStatusCode];
    [owner_ emit:@"securityChanged" fields:@{@"security" : SecurityOf(browser, ToNS(frame->GetURL()))}];
  }

  void OnLoadError(CefRefPtr<CefBrowser>,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override {
    if (!frame->IsMain()) {
      return;
    }
    [owner_ emit:@"navigationFailed"
          fields:@{
            @"failure" : @{
              @"kind" : FailureKind(errorCode),
              @"url" : JSONString(failedUrl),
              @"isProvisional" : @YES,
              @"engineCode" : @(errorCode),
              @"description" : ToNS(errorText),
            }
          }];
  }

  bool OnBeforePopup(CefRefPtr<CefBrowser>,
                     CefRefPtr<CefFrame>,
                     int,
                     const CefString& target_url,
                     const CefString&,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures&,
                     CefWindowInfo&,
                     CefRefPtr<CefClient>&,
                     CefBrowserSettings&,
                     CefRefPtr<CefDictionaryValue>&,
                     bool*) override {
    // Refrax owns every window and tab, so popups become requests.
    RequestOpen(target_url, target_disposition, user_gesture);
    return true;
  }

  void OnBeforeClose(CefRefPtr<CefBrowser>) override { [owner_ handleBeforeClose]; }

  bool OnOpenURLFromTab(CefRefPtr<CefBrowser>,
                        CefRefPtr<CefFrame>,
                        const CefString& target_url,
                        WindowOpenDisposition target_disposition,
                        bool user_gesture) override {
    // ⌘-click and middle-click arrive here with a new-tab disposition.
    if (target_disposition == CEF_WOD_CURRENT_TAB) {
      return false;
    }
    RequestOpen(target_url, target_disposition, user_gesture);
    return true;
  }

  void OnRenderProcessTerminated(CefRefPtr<CefBrowser>, TerminationStatus status, int, const CefString&) override {
    NSString* reason = status == TS_PROCESS_OOM ? @"exceededMemoryLimit" : @"crashed";
    [owner_ emit:@"rendererHealthChanged" fields:@{@"health" : @{@"terminated" : @{@"reason" : reason}}}];
  }

  bool OnBeforeDownload(CefRefPtr<CefBrowser>,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString& suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override {
    NSString* mimeType = ToNS(download_item->GetMimeType());
    [owner_ request:@"download"
             fields:@{
               @"url" : ToNS(download_item->GetURL()),
               @"suggestedFilename" : ToNS(suggested_name),
               @"mimeType" : mimeType.length ? mimeType : NSNull.null,
             }
              reply:^(NSString* name, NSDictionary* fields) {
                NSString* path = [name isEqualToString:@"saveTo"] ? FilePath(fields[@"url"]) : nil;
                if (path) {
                  callback->Continue(ToStd(path), false);
                }
              }];
    return true;
  }

  // MARK: Dialogs — Refrax shows them in the page's pane and answers through the contract.

  bool OnJSDialog(CefRefPtr<CefBrowser>,
                  const CefString& origin_url,
                  JSDialogType dialog_type,
                  const CefString& message_text,
                  const CefString& default_prompt_text,
                  CefRefPtr<CefJSDialogCallback> callback,
                  bool&) override {
    NSString* kind = dialog_type == JSDIALOGTYPE_CONFIRM ? @"confirm" : dialog_type == JSDIALOGTYPE_PROMPT ? @"prompt" : @"alert";
    NSString* defaultText = dialog_type == JSDIALOGTYPE_PROMPT ? Capped(ToNS(default_prompt_text)) : nil;
    RequestDialog(kind, Capped(ToNS(message_text)), defaultText, ToNS(origin_url), callback);
    return true;
  }

  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser>,
                            const CefString& message_text,
                            bool,
                            CefRefPtr<CefJSDialogCallback> callback) override {
    RequestDialog(@"beforeUnload", Capped(ToNS(message_text)), nil, [owner_ lastCommittedURL], callback);
    return true;
  }

  // MARK: Permissions — Refrax decides from site settings or asks the user.

  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>,
                                      CefRefPtr<CefFrame>,
                                      const CefString& requesting_origin,
                                      uint32_t requested_permissions,
                                      CefRefPtr<CefMediaAccessCallback> callback) override {
    constexpr uint32_t desktop = CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE;
    bool audio = requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE;
    bool video = requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;
    NSString* kind = (requested_permissions & desktop) ? @"screenCapture"
                     : audio && video                  ? @"cameraAndMicrophone"
                     : video                           ? @"camera"
                                                       : @"microphone";
    RequestPermission(kind, ToNS(requesting_origin), ^(bool allowed) {
      callback->Continue(allowed ? requested_permissions : CEF_MEDIA_PERMISSION_NONE);
    });
    return true;
  }

  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>,
                              uint64_t,
                              const CefString& requesting_origin,
                              uint32_t requested_permissions,
                              CefRefPtr<CefPermissionPromptCallback> callback) override {
    NSString* kind = PermissionKind(requested_permissions);
    if (!kind) {
      // A permission Refrax has no setting or prompt for.
      callback->Continue(CEF_PERMISSION_RESULT_DENY);
      return true;
    }
    RequestPermission(kind, ToNS(requesting_origin), ^(bool allowed) {
      callback->Continue(allowed ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY);
    });
    return true;
  }

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>,
                              int message_id,
                              bool success,
                              const void* result,
                              size_t result_size) override {
    [owner_ handleDevToolsResult:message_id success:success data:[NSData dataWithBytes:result length:result_size]];
  }

  void OnDevToolsEvent(CefRefPtr<CefBrowser>, const CefString& method, const void* params, size_t params_size) override {
    [owner_ handleDevToolsEvent:ToNS(method) params:[NSData dataWithBytes:params length:params_size]];
  }

  void Detach() { owner_ = nil; }

 private:
  void RequestOpen(const CefString& url, WindowOpenDisposition disposition, bool user_gesture) {
    NSString* target = ToNS(url);
    if (!target.length) {
      return;
    }
    [owner_ request:@"openURL"
             fields:@{@"url" : target, @"disposition" : DispositionName(disposition), @"userGesture" : @(user_gesture)}
              reply:^(NSString*, NSDictionary*){
              }];
  }

  void RequestDialog(NSString* kind,
                     NSString* message,
                     NSString* defaultText,
                     NSString* origin,
                     CefRefPtr<CefJSDialogCallback> callback) {
    NSDictionary* dialog = @{
      @"kind" : kind,
      @"message" : message ?: @"",
      @"defaultText" : defaultText ?: NSNull.null,
      @"origin" : origin.length ? origin : NSNull.null,
    };
    [owner_ request:@"javaScriptDialog"
             fields:@{@"dialog" : dialog}
              reply:^(NSString* name, NSDictionary* fields) {
                NSString* text = [fields[@"text"] isKindOfClass:NSString.class] ? fields[@"text"] : @"";
                callback->Continue([name isEqualToString:@"confirm"], ToStd(text));
              }];
  }

  void RequestPermission(NSString* kind, NSString* origin, void (^decided)(bool allowed)) {
    [owner_ request:@"permission"
             fields:@{@"kind" : kind, @"origin" : origin}
              reply:^(NSString* name, NSDictionary*) {
                decided([name isEqualToString:@"allow"]);
              }];
  }

  /// The contract kind for a single permission, or nil for one Refrax doesn't model.
  static NSString* PermissionKind(uint32_t permissions) {
    switch (permissions) {
      case CEF_PERMISSION_TYPE_GEOLOCATION:
        return @"geolocation";
      case CEF_PERMISSION_TYPE_NOTIFICATIONS:
        return @"notifications";
      case CEF_PERMISSION_TYPE_CLIPBOARD:
        return @"clipboardRead";
      case CEF_PERMISSION_TYPE_CAMERA_STREAM:
        return @"camera";
      case CEF_PERMISSION_TYPE_MIC_STREAM:
        return @"microphone";
      case CEF_PERMISSION_TYPE_CAMERA_STREAM | CEF_PERMISSION_TYPE_MIC_STREAM:
        return @"cameraAndMicrophone";
      default:
        return nil;
    }
  }

  /// Dialog text within the contract's string cap (8 KiB).
  static NSString* Capped(NSString* text) {
    constexpr NSUInteger limit = 2000;
    return text.length > limit ? [[text substringToIndex:limit] stringByAppendingString:@"…"] : text;
  }

  static NSString* SecurityOf(CefRefPtr<CefBrowser> browser, NSString* url) {
    NSString* scheme = [NSURL URLWithString:url].scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"]) {
      return @"insecure";
    }
    if (![scheme isEqualToString:@"https"]) {
      return @"notApplicable";
    }
    CefRefPtr<CefNavigationEntry> entry = browser->GetHost()->GetVisibleNavigationEntry();
    CefRefPtr<CefSSLStatus> ssl = entry ? entry->GetSSLStatus() : nullptr;
    if (!ssl || !ssl->IsSecureConnection()) {
      return @"insecure";
    }
    return ssl->GetContentStatus() == SSL_CONTENT_NORMAL_CONTENT ? @"secure" : @"mixedContent";
  }

  __weak RFXChromiumPage* owner_;
  CefRefPtr<Blocker> blocker_ = new Blocker();

  IMPLEMENT_REFCOUNTING(Client);
};

/// Browser-process hooks: command-line policy and the message pump schedule.
class App : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  void OnBeforeCommandLineProcessing(const CefString& process_type, CefRefPtr<CefCommandLine> command_line) override {
    if (!process_type.empty()) {
      return;
    }
    // Chromium's cookie encryption otherwise asks for the login keychain under
    // Chromium's own item name on first use.
    command_line->AppendSwitch("use-mock-keychain");
    // The media router's DIAL/mDNS discovery triggers the Local Network privacy prompt.
    command_line->AppendSwitchWithValue("disable-features", "MediaRouter,DialMediaRouteProvider");
    command_line->AppendSwitch("disable-component-update");
  }

  void OnContextInitialized() override { [[RFXChromiumEngineHost current] contextDidInitialize]; }

  void OnScheduleMessagePumpWork(int64_t delay_ms) override {
    // Called from any thread.
    dispatch_async(dispatch_get_main_queue(), ^{
      [[RFXChromiumEngineHost current] scheduleWorkAfter:delay_ms];
    });
  }

 private:
  IMPLEMENT_REFCOUNTING(App);
};

}  // namespace

// MARK: - Container view

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

// MARK: - Page

@implementation RFXChromiumPage {
  RFXChromiumContainerView* _container;
  CefRefPtr<CefRequestContext> _requestContext;
  CefRefPtr<Client> _client;
  CefRefPtr<CefBrowser> _browser;
  CefRefPtr<CefRegistration> _devToolsRegistration;
  NSString* _pendingURL;
  NSString* _lastCommittedURL;
  BOOL _hidden;
  BOOL _closed;
  double _zoomFactor;
  int _nextMessageID;
  NSMutableDictionary<NSNumber*, void (^)(NSDictionary*, NSError*)>* _pendingDevToolsCalls;
  NSMutableArray<NSString*>* _installedScriptIdentifiers;
  /// Binding name → channels that world's scripts may post to.
  NSMutableDictionary<NSString*, NSSet<NSString*>*>* _channelsByBinding;
  /// Binding name → the global that settles that world's pending calls; fixed for the page's life.
  NSMutableDictionary<NSString*, NSString*>* _resolversByBinding;
  /// Binding name → the contract world its scripts run in.
  NSMutableDictionary<NSString*, NSDictionary*>* _worldsByBinding;
}

@synthesize delegate = _delegate;

- (instancetype)initWithURL:(NSString*)url requestContext:(CefRefPtr<CefRequestContext>)context {
  if ((self = [super init])) {
    _container = [[RFXChromiumContainerView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    _container.owner = self;
    _container.wantsLayer = YES;
    _requestContext = context;
    _pendingURL = url;
    _zoomFactor = 1.0;
    _nextMessageID = 1;
    _pendingDevToolsCalls = [NSMutableDictionary dictionary];
    _installedScriptIdentifiers = [NSMutableArray array];
    _channelsByBinding = [NSMutableDictionary dictionary];
    _resolversByBinding = [NSMutableDictionary dictionary];
    _worldsByBinding = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSView*)view {
  return _container;
}

// MARK: Events

- (void)emit:(NSString*)name fields:(NSDictionary*)fields {
  [_delegate enginePage:self didEmitEvent:Message(name, fields)];
}

- (void)request:(NSString*)name fields:(NSDictionary*)fields reply:(void (^)(NSString*, NSDictionary*))reply {
  id<RFXEnginePageDelegate> delegate = _delegate;
  if (!delegate) {
    reply(@"cancel", @{});
    return;
  }
  [delegate enginePage:self
            didRequest:Message(name, fields)
                 reply:^(NSData* answer) {
                   NSString* answerName = @"cancel";
                   NSDictionary* answerFields = @{};
                   ParseCase(answer, &answerName, &answerFields);
                   reply(answerName, answerFields);
                 }];
}

- (nullable NSString*)lastCommittedURL {
  return _lastCommittedURL;
}

- (void)handleCommitWithURL:(NSString*)url isBackForward:(BOOL)isBackForward {
  _lastCommittedURL = url;
  [self emit:@"navigationCommitted" fields:@{@"url" : url, @"isBackForward" : @(isBackForward)}];
}

- (void)handleFinishWithURL:(NSString*)url statusCode:(int)statusCode {
  [self emit:@"navigationFinished" fields:@{@"url" : url, @"statusCode" : statusCode > 0 ? @(statusCode) : NSNull.null}];
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
  RFXChromiumEngineHost* host = [RFXChromiumEngineHost current];
  if (_browser || _closed || !_container.window || !host.isContextReady) {
    return;
  }
  NSRect bounds = _container.bounds;
  CefWindowInfo windowInfo;
  windowInfo.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(_container),
                        CefRect(0, 0, static_cast<int>(NSWidth(bounds)), static_cast<int>(NSHeight(bounds))));
  CefBrowserSettings settings;
  _client = new Client(self);
  NSString* initialURL = _pendingURL ?: @"about:blank";
  _pendingURL = nil;
  _browser = CefBrowserHost::CreateBrowserSync(windowInfo, _client, ToStd(initialURL), settings, nullptr, _requestContext);
  if (!_browser) {
    NSLog(@"[RFXChromium] CreateBrowserSync failed for %@", initialURL);
    return;
  }
  _devToolsRegistration = _browser->GetHost()->AddDevToolsMessageObserver(_client);
  // Blink's page agent injects new-document scripts only while the Page domain is
  // enabled, and Runtime.bindingCalled is delivered only while Runtime is.
  [self callDevTools:@"Page.enable" params:@{} completion:nil];
  [self callDevTools:@"Runtime.enable" params:@{} completion:nil];
  [self installScripts:[RFXChromiumEngineHost current].scripts];
  [self applyZoom];
  [self containerDidLayout];
}

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
  _delegate = nil;
  _devToolsRegistration = nullptr;
  if (_browser) {
    _browser->GetHost()->CloseBrowser(true);
  } else {
    [self handleBeforeClose];
  }
  for (void (^completion)(NSDictionary*, NSError*) in _pendingDevToolsCalls.allValues) {
    completion(nil, MakeError(3, @"The page closed before the DevTools call finished."));
  }
  [_pendingDevToolsCalls removeAllObjects];
}

- (void)handleBeforeClose {
  if (_client) {
    _client->Detach();
  }
  _browser = nullptr;
  _client = nullptr;
  [[RFXChromiumEngineHost current] pageDidClose:self];
}

// MARK: Commands

- (void)performCommand:(NSData*)command {
  NSString* name = nil;
  NSDictionary* fields = nil;
  if (!ParseCase(command, &name, &fields)) {
    return;
  }
  CefRefPtr<CefBrowserHost> host = _browser ? _browser->GetHost() : nullptr;

  if ([name isEqualToString:@"load"]) {
    NSString* url = fields[@"request"][@"url"];
    if (![url isKindOfClass:NSString.class]) {
      return;
    }
    if (_browser) {
      _browser->GetMainFrame()->LoadURL(ToStd(url));
    } else {
      _pendingURL = url;
    }
  } else if ([name isEqualToString:@"goBack"]) {
    if (_browser) _browser->GoBack();
  } else if ([name isEqualToString:@"goForward"]) {
    if (_browser) _browser->GoForward();
  } else if ([name isEqualToString:@"reload"]) {
    if (_browser) {
      [fields[@"fromOrigin"] boolValue] ? _browser->ReloadIgnoreCache() : _browser->Reload();
    }
  } else if ([name isEqualToString:@"stopLoading"]) {
    if (_browser) _browser->StopLoad();
  } else if ([name isEqualToString:@"setZoom"]) {
    double factor = [fields[@"factor"] doubleValue];
    if (factor > 0) {
      _zoomFactor = factor;
      [self applyZoom];
      [self emit:@"zoomChanged" fields:@{@"factor" : @(factor)}];
    }
  } else if ([name isEqualToString:@"setAudioMuted"]) {
    if (host) host->SetAudioMuted([fields[@"muted"] boolValue]);
  } else if ([name isEqualToString:@"find"]) {
    NSDictionary* query = fields[@"query"];
    NSString* text = query[@"text"];
    if (host && [text isKindOfClass:NSString.class]) {
      host->Find(ToStd(text), [query[@"forward"] boolValue], [query[@"matchCase"] boolValue],
                 [query[@"findNext"] boolValue]);
    }
  } else if ([name isEqualToString:@"stopFinding"]) {
    if (host) host->StopFinding(true);
  } else if ([name isEqualToString:@"setVisibility"]) {
    _hidden = [fields[@"visibility"] isEqual:@"hidden"];
    if (host) host->WasHidden(_hidden || _container.window == nil);
  } else if ([name isEqualToString:@"focus"]) {
    if (host) host->SetFocus(true);
  } else if ([name isEqualToString:@"devTools"]) {
    if (host && fields[@"command"][@"show"]) {
      CefWindowInfo windowInfo;
      CefBrowserSettings settings;
      host->ShowDevTools(windowInfo, nullptr, settings, CefPoint());
    } else if (host && fields[@"command"][@"hide"]) {
      host->CloseDevTools();
    }
  }
}

- (void)applyZoom {
  if (_browser) {
    // Chromium zoom levels are logarithmic: factor = 1.2 ^ level.
    _browser->GetHost()->SetZoomLevel(log(_zoomFactor) / log(1.2));
  }
}

// MARK: DevTools protocol

/// Calls a DevTools protocol method on this page's browser.
- (void)callDevTools:(NSString*)method
              params:(NSDictionary*)params
          completion:(nullable void (^)(NSDictionary* _Nullable result, NSError* _Nullable error))completion {
  if (!_browser) {
    if (completion) completion(nil, MakeError(1, @"The page has not been created yet."));
    return;
  }
  NSData* json = [NSJSONSerialization dataWithJSONObject:params ?: @{} options:0 error:nil];
  CefRefPtr<CefValue> value =
      CefParseJSON(ToStd([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]), JSON_PARSER_RFC);
  CefRefPtr<CefDictionaryValue> dictionary = value ? value->GetDictionary() : nullptr;
  int messageID = _nextMessageID++;
  if (completion) {
    _pendingDevToolsCalls[@(messageID)] = [completion copy];
  }
  if (_browser->GetHost()->ExecuteDevToolsMethod(messageID, ToStd(method), dictionary) == 0) {
    [_pendingDevToolsCalls removeObjectForKey:@(messageID)];
    if (completion) completion(nil, MakeError(2, [NSString stringWithFormat:@"%@ could not be sent.", method]));
  }
}

- (void)handleDevToolsResult:(int)messageID success:(BOOL)success data:(NSData*)data {
  void (^completion)(NSDictionary*, NSError*) = _pendingDevToolsCalls[@(messageID)];
  if (!completion) {
    return;
  }
  [_pendingDevToolsCalls removeObjectForKey:@(messageID)];
  NSDictionary* json = ParseObject(data);
  if (!success || !json) {
    completion(nil, MakeError(4, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"DevTools error"));
  } else {
    completion(json, nil);
  }
}

- (void)handleDevToolsEvent:(NSString*)method params:(NSData*)paramsData {
  if (![method isEqualToString:@"Runtime.bindingCalled"]) {
    return;
  }
  NSDictionary* params = ParseObject(paramsData);
  NSSet<NSString*>* allowed = _channelsByBinding[params[@"name"]];
  NSString* payload = params[@"payload"];
  if (!allowed || ![payload isKindOfClass:NSString.class]) {
    return;
  }
  NSDictionary* message = ParseObject([payload dataUsingEncoding:NSUTF8StringEncoding]);
  NSString* channel = message[@"channel"];
  NSNumber* callID = message[@"id"];
  NSNumber* contextID = params[@"executionContextId"];
  // A script may only post on channels granted to its world.
  if (![channel isKindOfClass:NSString.class] || ![allowed containsObject:channel] ||
      ![callID isKindOfClass:NSNumber.class] || ![contextID isKindOfClass:NSNumber.class]) {
    return;
  }
  NSData* delivered = [NSJSONSerialization dataWithJSONObject:@{
    @"channel" : channel,
    @"world" : _worldsByBinding[params[@"name"]] ?: @{@"page" : @{}},
    @"body" : message[@"body"] ?: NSNull.null,
    @"frameURL" : _lastCommittedURL ?: NSNull.null,
    @"isMainFrame" : @YES,
  } options:0 error:nil];
  NSString* resolver = _resolversByBinding[params[@"name"]];
  __weak RFXChromiumPage* weakSelf = self;
  [_delegate enginePage:self
      didReceiveScriptMessage:delivered
                        reply:^(NSData* reply) {
                          [weakSelf settleScriptCall:callID.longLongValue
                                            resolver:resolver
                                             context:contextID
                                               reply:reply];
                        }];
}

/// Settles a `postMessage` promise in the execution context that made the call.
- (void)settleScriptCall:(long long)callID resolver:(NSString*)resolver context:(NSNumber*)context reply:(NSData*)reply {
  NSString* json = [[NSString alloc] initWithData:reply encoding:NSUTF8StringEncoding];
  if (!resolver || !ParseObject(reply)) {
    json = @"{\"error\":{\"message\":\"Invalid reply\"}}";
  }
  NSString* expression = [NSString stringWithFormat:@"globalThis['%@'] && globalThis['%@'](%lld, %@)", resolver, resolver, callID, json];
  [self callDevTools:@"Runtime.evaluate" params:@{@"expression" : expression, @"contextId" : context} completion:nil];
}

// MARK: Injected scripts

/// Installs Refrax's scripts in this page, replacing the previous set.
///
/// Each world gets a binding scoped to it and a prelude giving its scripts the
/// same `window.webkit.messageHandlers.<channel>.postMessage(body)` call they
/// use in WebKit, limited to the channels granted to that world.
- (void)installScripts:(NSArray<NSDictionary*>*)scripts {
  if (!_browser) {
    return;
  }
  for (NSString* identifier in _installedScriptIdentifiers) {
    [self callDevTools:@"Page.removeScriptToEvaluateOnNewDocument" params:@{@"identifier" : identifier} completion:nil];
  }
  [_installedScriptIdentifiers removeAllObjects];

  NSMutableDictionary<NSString*, NSMutableSet<NSString*>*>* channelsByWorld = [NSMutableDictionary dictionary];
  for (NSDictionary* script in scripts) {
    NSString* world = [self worldNameOf:script] ?: @"";
    NSMutableSet* channels = channelsByWorld[world] ?: [NSMutableSet set];
    [channels addObjectsFromArray:script[@"channels"] ?: @[]];
    channelsByWorld[world] = channels;
  }

  for (NSString* world in channelsByWorld) {
    NSSet<NSString*>* channels = channelsByWorld[world];
    if (channels.count == 0) {
      continue;
    }
    NSString* binding = [NSString stringWithFormat:@"__refraxChannel%lu", (unsigned long)world.hash];
    _channelsByBinding[binding] = channels;
    NSString* resolver = _resolversByBinding[binding] ?: [NSString stringWithFormat:@"__refraxSettle%@",
        [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
    _resolversByBinding[binding] = resolver;
    _worldsByBinding[binding] = world.length ? @{@"isolated" : @{@"name" : world}} : @{@"page" : @{}};
    NSMutableDictionary* bindingParams = [@{@"name" : binding} mutableCopy];
    if (world.length) {
      bindingParams[@"executionContextName"] = world;
    }
    [self callDevTools:@"Runtime.addBinding" params:bindingParams completion:nil];
    [self addScript:[self preludeForBinding:binding resolver:resolver channels:channels] world:world];
  }

  for (NSDictionary* script in scripts) {
    NSString* source = script[@"source"];
    if (![source isKindOfClass:NSString.class]) {
      continue;
    }
    if ([script[@"mainFrameOnly"] boolValue]) {
      source = [NSString stringWithFormat:@"if (window.top === window) {\n%@\n}", source];
    }
    if ([script[@"injectionTime"] isEqual:@"documentEnd"]) {
      source = [NSString stringWithFormat:
          @"(function(run){ document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', run, {once: true}) : run(); })(function() {\n%@\n});",
          source];
    }
    [self addScript:source world:[self worldNameOf:script] ?: @""];
  }
}

- (nullable NSString*)worldNameOf:(NSDictionary*)script {
  NSDictionary* world = script[@"world"];
  NSString* name = [world isKindOfClass:NSDictionary.class] ? world[@"isolated"][@"name"] : nil;
  return [name isKindOfClass:NSString.class] ? name : nil;
}

- (void)addScript:(NSString*)source world:(NSString*)world {
  NSMutableDictionary* params = [@{@"source" : source, @"runImmediately" : @YES} mutableCopy];
  if (world.length) {
    params[@"worldName"] = world;
  }
  __weak RFXChromiumPage* weakSelf = self;
  [self callDevTools:@"Page.addScriptToEvaluateOnNewDocument"
              params:params
          completion:^(NSDictionary* result, NSError*) {
            NSString* identifier = result[@"identifier"];
            if ([identifier isKindOfClass:NSString.class]) {
              [weakSelf recordScriptIdentifier:identifier];
            }
          }];
}

- (void)recordScriptIdentifier:(NSString*)identifier {
  [_installedScriptIdentifiers addObject:identifier];
}

/// The prelude gives each call an id and a pending promise, settled when Refrax's reply
/// is evaluated into the same context through `resolver`. The resolver's name is random
/// per install; in the page world the page can still reach it, which only lets the page
/// settle its own calls early.
- (NSString*)preludeForBinding:(NSString*)binding resolver:(NSString*)resolver channels:(NSSet<NSString*>*)channels {
  NSData* names = [NSJSONSerialization dataWithJSONObject:channels.allObjects options:0 error:nil];
  return [NSString stringWithFormat:
      @"(function() {"
       "const post = globalThis['%@'];"
       "if (typeof post !== 'function') return;"
       "delete globalThis['%@'];"
       "const pending = new Map();"
       "let nextID = 1;"
       "Object.defineProperty(globalThis, '%@', { value(id, reply) {"
       "  const call = pending.get(id);"
       "  if (!call) return;"
       "  pending.delete(id);"
       "  if (reply && reply.value) call.resolve(reply.value.value);"
       "  else call.reject(new Error(reply && reply.error ? reply.error.message : 'No reply'));"
       "} });"
       "const handlers = {};"
       "for (const channel of %@) {"
       "  handlers[channel] = Object.freeze({ postMessage(body) {"
       "    const id = nextID++;"
       "    return new Promise((resolve, reject) => {"
       "      pending.set(id, { resolve, reject });"
       "      post(JSON.stringify({ channel, body, id }));"
       "    });"
       "  } });"
       "}"
       "globalThis.webkit = Object.freeze({ messageHandlers: Object.freeze(handlers) });"
       "})();",
      binding, binding, resolver, [[NSString alloc] initWithData:names encoding:NSUTF8StringEncoding]];
}

// MARK: JavaScript

- (void)evaluateScript:(NSData*)requestData completion:(void (^)(NSData*, NSError*))completion {
  NSDictionary* request = ParseObject(requestData);
  NSString* source = request[@"source"];
  if (![source isKindOfClass:NSString.class]) {
    completion(nil, MakeError(6, @"The script request has no source."));
    return;
  }
  NSDictionary* params = @{
    @"expression" : source,
    @"returnByValue" : @YES,
    @"awaitPromise" : @YES,
    @"userGesture" : @([request[@"userGesture"] boolValue]),
  };
  [self callDevTools:@"Runtime.evaluate"
              params:params
          completion:^(NSDictionary* json, NSError* error) {
            if (error) {
              completion(nil, error);
              return;
            }
            NSDictionary* exception = json[@"exceptionDetails"];
            if (exception) {
              NSString* message = exception[@"exception"][@"description"] ?: exception[@"text"] ?: @"JavaScript exception";
              completion(nil, MakeError(5, message));
              return;
            }
            id value = json[@"result"][@"value"] ?: NSNull.null;
            completion([NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:nil], nil);
          }];
}

// MARK: Snapshots

- (void)snapshotRect:(NSRect)rect completion:(void (^)(CGImageRef, NSError*))completion {
  completion(nil, MakeError(7, @"Snapshots need off-screen rendering, which the in-process engine doesn't use."));
}

@end

// MARK: - Engine host

@implementation RFXChromiumEngineHost {
  NSArray<NSDictionary*>* _scripts;
  CefRefPtr<App> _app;
  RFXChromiumPump* _pump;
  BOOL _running;
  BOOL _contextReady;
  NSString* _storagePath;
  std::map<std::string, CefRefPtr<CefRequestContext>> _contexts;
  NSHashTable<RFXChromiumPage*>* _waitingForContext;
  NSMutableSet<RFXChromiumPage*>* _livePages;
}

@synthesize delegate = _delegate;
@synthesize scripts = _scripts;

static __weak RFXChromiumEngineHost* g_current;

+ (instancetype)current {
  return g_current;
}

- (instancetype)init {
  if ((self = [super init])) {
    _waitingForContext = [NSHashTable weakObjectsHashTable];
    _livePages = [NSMutableSet set];
  }
  return self;
}

- (BOOL)isContextReady {
  return _contextReady;
}

- (void)startWithConfiguration:(NSData*)configurationData completion:(void (^)(NSError*))completion {
  if (_running) {
    completion(nil);
    return;
  }
  if (g_current && g_current != self) {
    completion(MakeError(10, @"Another Chromium engine instance is already running in this process."));
    return;
  }
  // CefInitialize creates Chromium's UI-thread message pump, which needs NSApp to
  // report whether -sendEvent: is on the stack.
  if (![NSApplication.sharedApplication conformsToProtocol:@protocol(CefAppProtocol)]) {
    completion(MakeError(14, @"The host application's NSApplication subclass must adopt CefAppProtocol."));
    return;
  }
  NSDictionary* configuration = ParseObject(configurationData);
  _storagePath = FilePath(configuration[@"storageDirectory"]);
  NSString* logPath = FilePath(configuration[@"logFile"]);
  if (!_storagePath) {
    completion(MakeError(11, @"The configuration has no storage directory."));
    return;
  }

  // Everything else lives inside this bundle: Contents/Frameworks holds the CEF
  // framework and the helper apps next to it.
  NSBundle* bundle = [NSBundle bundleForClass:self.class];
  NSString* frameworks = bundle.privateFrameworksPath;
  NSString* frameworkPath = [frameworks stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
  NSString* helperPath = [frameworks
      stringByAppendingPathComponent:@"Refrax Chromium Helper.app/Contents/MacOS/Refrax Chromium Helper"];

  // Resolve every cef_* entry point from the framework before any CEF call.
  NSString* binary = [frameworkPath stringByAppendingPathComponent:@"Chromium Embedded Framework"];
  if (!cef_load_library(binary.fileSystemRepresentation)) {
    completion(MakeError(12, [NSString stringWithFormat:@"cef_load_library failed for %@", binary]));
    return;
  }

  g_current = self;
  _pump = [[RFXChromiumPump alloc] init];
  _app = new App();

  CefSettings settings;
  settings.no_sandbox = true;
  settings.external_message_pump = true;
  settings.multi_threaded_message_loop = false;
  settings.persist_session_cookies = true;
  settings.log_severity = LOGSEVERITY_WARNING;
  CefString(&settings.framework_dir_path) = ToStd(frameworkPath);
  CefString(&settings.browser_subprocess_path) = ToStd(helperPath);
  CefString(&settings.main_bundle_path) = ToStd(NSBundle.mainBundle.bundlePath);
  CefString(&settings.root_cache_path) = ToStd(_storagePath);
  CefString(&settings.cache_path) = ToStd([_storagePath stringByAppendingPathComponent:@"Shared"]);
  if (logPath) {
    CefString(&settings.log_file) = ToStd(logPath);
  }

  // Chromium parses argv for switches; hand it only the executable so the
  // app's own launch arguments are never interpreted as Chromium switches.
  static char* argv0 = strdup(NSProcessInfo.processInfo.arguments.firstObject.fileSystemRepresentation);
  static char* argv[] = {argv0, nullptr};
  CefMainArgs mainArgs(1, argv);

  if (!CefInitialize(mainArgs, settings, _app, nullptr)) {
    g_current = nil;
    completion(MakeError(13, [NSString stringWithFormat:@"CefInitialize failed (exit code %d)", CefGetExitCode()]));
    return;
  }
  _running = YES;
  [_pump scheduleWorkAfter:0];
  completion(nil);
}

- (void)contextDidInitialize {
  _contextReady = YES;
  for (RFXChromiumPage* page in _waitingForContext.allObjects) {
    [page contextDidBecomeReady];
  }
  [_waitingForContext removeAllObjects];
}

- (void)scheduleWorkAfter:(int64_t)delayMs {
  [_pump scheduleWorkAfter:delayMs];
}

/// Profile directory relative to the storage directory, or nil for in-memory.
- (nullable NSString*)relativePathForProfile:(NSDictionary*)profile {
  if (profile[@"isolated"]) {
    return [@"Isolated" stringByAppendingPathComponent:profile[@"isolated"][@"id"] ?: @"unknown"];
  }
  if (profile[@"ephemeral"]) {
    return nil;
  }
  return @"Shared";
}

- (CefRefPtr<CefRequestContext>)requestContextForProfile:(NSDictionary*)profile {
  NSString* relative = [self relativePathForProfile:profile];
  std::string key = relative ? ToStd(relative) : ToStd([NSString stringWithFormat:@"ephemeral:%@", profile[@"ephemeral"][@"id"]]);
  auto existing = _contexts.find(key);
  if (existing != _contexts.end()) {
    return existing->second;
  }
  CefRequestContextSettings settings;
  settings.persist_session_cookies = true;
  if (relative) {
    // Must be a child of root_cache_path.
    CefString(&settings.cache_path) = ToStd([_storagePath stringByAppendingPathComponent:relative]);
  }
  CefRefPtr<CefRequestContext> context = CefRequestContext::CreateContext(settings, nullptr);
  _contexts[key] = context;
  return context;
}

- (id<RFXEnginePage>)makePageWithSpec:(NSData*)specData error:(NSError**)error {
  NSDictionary* spec = ParseObject(specData);
  if (!_running || !spec) {
    if (error) *error = MakeError(15, _running ? @"The page spec is malformed." : @"The engine is not running.");
    return nil;
  }
  NSDictionary* profile = [spec[@"profile"] isKindOfClass:NSDictionary.class] ? spec[@"profile"] : @{@"shared" : @{}};
  NSString* url = [spec[@"initialURL"] isKindOfClass:NSString.class] ? spec[@"initialURL"] : nil;
  RFXChromiumPage* page = [[RFXChromiumPage alloc] initWithURL:url requestContext:[self requestContextForProfile:profile]];
  [_livePages addObject:page];
  if (!_contextReady) {
    [_waitingForContext addObject:page];
  }
  return page;
}

- (void)applyPolicy:(NSData*)update {
  NSString* name = nil;
  NSDictionary* fields = nil;
  if (!ParseCase(update, &name, &fields)) {
    return;
  }
  // Extensions and site settings aren't applied by this engine.
  if ([name isEqualToString:@"contentBlocking"]) {
    NSDictionary* policy = fields[@"policy"];
    BOOL enabled = [policy[@"isEnabled"] boolValue];
    NSMutableArray<NSString*>* lists = [NSMutableArray array];
    for (NSDictionary* list in policy[@"lists"]) {
      if ([list[@"contents"] isKindOfClass:NSString.class]) {
        [lists addObject:list[@"contents"]];
      }
    }
    if (!enabled) {
      SetRules(nullptr);
      return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      SetRules(ParseRules(lists));
    });
  } else if ([name isEqualToString:@"scripts"] && [fields[@"scripts"] isKindOfClass:NSArray.class]) {
    _scripts = [fields[@"scripts"] copy];
    for (RFXChromiumPage* page in _livePages) {
      [page installScripts:_scripts];
    }
  }
}

- (void)removeProfile:(NSData*)profileData completion:(void (^)(void))completion {
  NSString* relative = [self relativePathForProfile:ParseObject(profileData) ?: @{}];
  if (relative && _storagePath) {
    NSString* path = [_storagePath stringByAppendingPathComponent:relative];
    _contexts.erase(ToStd(relative));
    [NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:nil error:nil];
  }
  completion();
}

- (void)pageDidClose:(RFXChromiumPage*)page {
  [_livePages removeObject:page];
}

- (void)shutdown {
  if (!_running) {
    return;
  }
  for (RFXChromiumPage* page in _livePages.allObjects) {
    [page close];
  }
  // Let the close messages reach the renderers before tearing down.
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
  while (_livePages.count && deadline.timeIntervalSinceNow > 0) {
    CefDoMessageLoopWork();
    [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  [_pump invalidate];
  _contexts.clear();
  _running = NO;
  if (_livePages.count == 0) {
    CefShutdown();
  }
}

@end
