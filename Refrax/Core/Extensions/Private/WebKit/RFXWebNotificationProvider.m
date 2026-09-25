@import WebKit;
#import "RFXWebNotificationProvider.h"

// MARK: - Value helpers

/// Converts and releases a copied WKStringRef.
static NSString *RFXTakeString(WKStringRef string) {
    if (!string) {
        return nil;
    }
    NSString *result = (__bridge_transfer NSString *)WKStringCopyCFString(kCFAllocatorDefault, string);
    WKRelease(string);
    return result;
}

static NSString *RFXOriginString(WKSecurityOriginRef origin) {
    return origin ? RFXTakeString(WKSecurityOriginCopyToString(origin)) : nil;
}

/// Runs `body` with a WebKit array of WKUInt64 values, released afterwards.
static void RFXWithIdentifierArray(NSArray<NSNumber *> *identifiers, void (^body)(WKArrayRef array)) {
    NSUInteger count = identifiers.count;
    WKTypeRef *values = calloc(MAX(count, 1), sizeof(WKTypeRef));
    for (NSUInteger index = 0; index < count; index++) {
        values[index] = WKUInt64Create(identifiers[index].unsignedLongLongValue);
    }
    WKArrayRef array = WKArrayCreate(values, count);
    body(array);
    WKRelease(array);
    for (NSUInteger index = 0; index < count; index++) {
        WKRelease(values[index]);
    }
    free(values);
}

/// Runs `body` with a WebKit array of security origins, released afterwards.
static void RFXWithOriginArray(NSArray<NSString *> *origins, void (^body)(WKArrayRef array)) {
    NSUInteger count = origins.count;
    WKTypeRef *values = calloc(MAX(count, 1), sizeof(WKTypeRef));
    for (NSUInteger index = 0; index < count; index++) {
        WKStringRef string = WKStringCreateWithUTF8CString(origins[index].UTF8String);
        values[index] = WKSecurityOriginCreateFromString(string);
        WKRelease(string);
    }
    WKArrayRef array = WKArrayCreate(values, count);
    body(array);
    WKRelease(array);
    for (NSUInteger index = 0; index < count; index++) {
        WKRelease(values[index]);
    }
    free(values);
}

// MARK: - RFXWebNotification

@interface RFXWebNotification ()
- (instancetype)initWithNotification:(WKNotificationRef)notification page:(WKPageRef)page;
@end

@implementation RFXWebNotification

- (instancetype)initWithNotification:(WKNotificationRef)notification page:(WKPageRef)page {
    if (!(self = [super init])) {
        return nil;
    }
    _identifier = WKNotificationGetID(notification);
    _title = RFXTakeString(WKNotificationCopyTitle(notification)) ?: @"";
    _body = RFXTakeString(WKNotificationCopyBody(notification)) ?: @"";
    _tag = RFXTakeString(WKNotificationCopyTag(notification)) ?: @"";
    _origin = RFXOriginString(WKNotificationGetSecurityOrigin(notification)) ?: @"";

    NSString *iconURL = RFXTakeString(WKNotificationCopyIconURL(notification));
    _iconURL = iconURL.length ? [NSURL URLWithString:iconURL] : nil;

    NSString *dataStoreIdentifier = RFXTakeString(WKNotificationCopyDataStoreIdentifier(notification));
    _dataStoreIdentifier = dataStoreIdentifier.length ? [[NSUUID alloc] initWithUUIDString:dataStoreIdentifier] : nil;

    _persistent = WKNotificationGetIsPersistent(notification);
    _silent = (WKNotificationGetAlert(notification) & kWKNotificationAlertSilent) != 0;
    _page = page;
    _dictionaryRepresentation = _persistent ? WKNotificationCopyDictionaryRepresentation(notification) : nil;
    return self;
}

@end

// MARK: - RFXWebNotificationProvider

@interface RFXWebNotificationProvider ()
- (instancetype)initWithManager:(WKNotificationManagerRef)manager NS_DESIGNATED_INITIALIZER;
- (void)detach;
@end

@implementation RFXWebNotificationProvider {
    WKNotificationManagerRef _manager;
    BOOL _installed;
}

static RFXWebNotificationProvider *RFXProviderFromClientInfo(const void *clientInfo) {
    return (__bridge RFXWebNotificationProvider *)clientInfo;
}

static void RFXShow(WKPageRef page, WKNotificationRef notification, const void *clientInfo) {
    RFXWebNotificationProvider *provider = RFXProviderFromClientInfo(clientInfo);
    RFXWebNotification *copy = [[RFXWebNotification alloc] initWithNotification:notification page:page];
    [provider.delegate notificationProvider:provider showNotification:copy];
}

static void RFXCancel(WKNotificationRef notification, const void *clientInfo) {
    RFXWebNotificationProvider *provider = RFXProviderFromClientInfo(clientInfo);
    [provider.delegate notificationProvider:provider cancelNotification:WKNotificationGetID(notification)];
}

static void RFXDidDestroy(WKNotificationRef notification, const void *clientInfo) {
    RFXWebNotificationProvider *provider = RFXProviderFromClientInfo(clientInfo);
    [provider.delegate notificationProvider:provider didDestroyNotification:WKNotificationGetID(notification)];
}

static void RFXAddManager(WKNotificationManagerRef manager, const void *clientInfo) {
}

static void RFXRemoveManager(WKNotificationManagerRef manager, const void *clientInfo) {
    RFXWebNotificationProvider *provider = RFXProviderFromClientInfo(clientInfo);
    [provider detach];
}

static WKDictionaryRef RFXPermissions(const void *clientInfo) {
    RFXWebNotificationProvider *provider = RFXProviderFromClientInfo(clientInfo);
    NSDictionary<NSString *, NSNumber *> *permissions = [provider.delegate notificationPermissionsForProvider:provider] ?: @{};

    NSUInteger count = permissions.count;
    WKStringRef *keys = calloc(MAX(count, 1), sizeof(WKStringRef));
    WKTypeRef *values = calloc(MAX(count, 1), sizeof(WKTypeRef));
    __block NSUInteger index = 0;
    [permissions enumerateKeysAndObjectsUsingBlock:^(NSString *origin, NSNumber *granted, BOOL *stop) {
        keys[index] = WKStringCreateWithUTF8CString(origin.UTF8String);
        values[index] = WKBooleanCreate(granted.boolValue);
        index++;
    }];
    // WebKit adopts the returned dictionary; the dictionary retains its keys and values.
    WKDictionaryRef dictionary = WKDictionaryCreate(keys, values, count);
    for (NSUInteger item = 0; item < count; item++) {
        WKRelease(keys[item]);
        WKRelease(values[item]);
    }
    free(keys);
    free(values);
    return dictionary;
}

static void RFXClear(WKArrayRef notificationIDs, const void *clientInfo) {
    RFXWebNotificationProvider *provider = RFXProviderFromClientInfo(clientInfo);
    size_t count = WKArrayGetSize(notificationIDs);
    NSMutableArray<NSNumber *> *identifiers = [NSMutableArray arrayWithCapacity:count];
    for (size_t index = 0; index < count; index++) {
        WKTypeRef item = WKArrayGetItemAtIndex(notificationIDs, index);
        if (item) {
            [identifiers addObject:@(WKUInt64GetValue((WKUInt64Ref)item))];
        }
    }
    [provider.delegate notificationProvider:provider clearNotifications:identifiers];
}

+ (NSUInteger)managerKeyForWebView:(WKWebView *)webView {
    return (NSUInteger)WKContextGetNotificationManager(WKPageGetContext(webView._pageRefForTransitionToWKWebView));
}

- (instancetype)initWithManager:(WKNotificationManagerRef)manager {
    if (!(self = [super init])) {
        return nil;
    }
    _manager = manager;
    return self;
}

- (instancetype)initWithWebView:(WKWebView *)webView {
    return [self initWithManager:WKContextGetNotificationManager(WKPageGetContext(webView._pageRefForTransitionToWKWebView))];
}

+ (instancetype)serviceWorkerProvider {
    return [[self alloc] initWithManager:WKNotificationManagerGetSharedServiceWorkerNotificationManager()];
}

- (void)dealloc {
    if (_manager && _installed) {
        WKNotificationManagerSetProvider(_manager, NULL);
    }
}

- (NSUInteger)managerKey {
    return (NSUInteger)_manager;
}

- (BOOL)isAttached {
    return _manager != NULL;
}

- (void)install {
    if (!_manager) {
        return;
    }
    WKNotificationProviderV0 provider = {
        .base = { .version = 0, .clientInfo = (__bridge const void *)self },
        .show = RFXShow,
        .cancel = RFXCancel,
        .didDestroyNotification = RFXDidDestroy,
        .addNotificationManager = RFXAddManager,
        .removeNotificationManager = RFXRemoveManager,
        .notificationPermissions = RFXPermissions,
        .clearNotifications = RFXClear,
    };
    WKNotificationManagerSetProvider(_manager, &provider.base);
    _installed = YES;
}

- (void)detach {
    _manager = NULL;
    [self.delegate notificationProviderDidDetach:self];
}

- (void)didShowNotification:(uint64_t)identifier {
    if (_manager) {
        WKNotificationManagerProviderDidShowNotification(_manager, identifier);
    }
}

- (void)didClickNotification:(uint64_t)identifier {
    if (_manager) {
        WKNotificationManagerProviderDidClickNotification(_manager, identifier);
    }
}

- (void)didCloseNotifications:(NSArray<NSNumber *> *)identifiers {
    WKNotificationManagerRef manager = _manager;
    if (!manager || !identifiers.count) {
        return;
    }
    RFXWithIdentifierArray(identifiers, ^(WKArrayRef array) {
        WKNotificationManagerProviderDidCloseNotifications(manager, array);
    });
}

- (void)updatePermission:(BOOL)allowed forOrigin:(NSString *)origin {
    if (!_manager) {
        return;
    }
    WKStringRef string = WKStringCreateWithUTF8CString(origin.UTF8String);
    WKSecurityOriginRef securityOrigin = WKSecurityOriginCreateFromString(string);
    WKNotificationManagerProviderDidUpdateNotificationPolicy(_manager, securityOrigin, allowed);
    WKRelease(securityOrigin);
    WKRelease(string);
}

- (void)removePermissionsForOrigins:(NSArray<NSString *> *)origins {
    WKNotificationManagerRef manager = _manager;
    if (!manager || !origins.count) {
        return;
    }
    RFXWithOriginArray(origins, ^(WKArrayRef array) {
        WKNotificationManagerProviderDidRemoveNotificationPolicies(manager, array);
    });
}

@end
