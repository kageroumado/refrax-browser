/**
 * WKNotificationPrivate.h
 * Refrax Browser
 *
 * WebKit SPI for the web Notifications API.
 *
 * ## How WebKit routes notifications (macOS)
 *
 * - **Page notifications** (`new Notification()`) go to the process pool's
 *   `WebNotificationManagerProxy`, which hands them to the provider installed with
 *   `WKNotificationManagerSetProvider` on `WKContextGetNotificationManager(pool)`.
 *   With no provider installed, WebKit's default provider drops them
 *   (WebNotificationManagerMessageHandler.cpp `showNotification`,
 *   WebNotificationManagerProxy.cpp `showImpl`).
 * - **Service worker notifications** (`registration.showNotification()`) go to
 *   `WebsiteDataStore::showPersistentNotification`: the data store delegate's
 *   `websiteDataStore:showNotification:` when implemented, otherwise the provider on
 *   `WKNotificationManagerGetSharedServiceWorkerNotificationManager()`
 *   (WebsiteDataStore.cpp `showPersistentNotification`).
 * - **Permissions** reach a web process when it launches: the data store delegate's
 *   `notificationPermissionsForWebsiteDataStore:` first, the pool provider's
 *   `notificationPermissions` when that is empty (WebProcessPool.cpp, process creation
 *   parameters). `WKNotificationManagerProviderDidUpdateNotificationPolicy` and
 *   `…DidRemoveNotificationPolicies` push changes to the running processes of that
 *   manager's pool (WebNotificationManagerProxy.cpp).
 * - **Ephemeral sessions** deny every request and report `default` without asking
 *   (WebNotificationClient.cpp `requestPermission`, `checkPermission`).
 *
 * Every WebKit object passed to a provider callback is valid only for the callback.
 *
 * ## Source references
 * - WebKit/Source/WebKit/UIProcess/API/C/WKNotificationProvider.h
 * - WebKit/Source/WebKit/UIProcess/API/C/WKNotificationManager.h
 * - WebKit/Source/WebKit/UIProcess/API/C/WKNotification.h
 * - WebKit/Source/WebKit/UIProcess/API/C/mac/WKNotificationPrivateMac.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKWebsiteDataStoreDelegate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStorePrivate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h
 */

#ifndef WKNotificationPrivate_h
#define WKNotificationPrivate_h

#import <WebKit/WebKit.h>
#import "WKFullScreenClientPrivate.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: - C API opaque types (WKBase.h)

typedef const struct OpaqueWKContext* WKContextRef;
typedef const struct OpaqueWKNotification* WKNotificationRef;
typedef const struct OpaqueWKNotificationManager* WKNotificationManagerRef;
typedef const struct OpaqueWKSecurityOrigin* WKSecurityOriginRef;
typedef const struct OpaqueWKString* WKStringRef;
typedef const struct OpaqueWKArray* WKArrayRef;
typedef const struct OpaqueWKDictionary* WKDictionaryRef;
typedef const struct OpaqueWKUInt64* WKUInt64Ref;
typedef const struct OpaqueWKBoolean* WKBooleanRef;

// MARK: - Notification provider (WKNotificationProvider.h)

typedef void (*WKNotificationProviderShowCallback)(WKPageRef _Nullable page, WKNotificationRef notification, const void* _Nullable clientInfo);
typedef void (*WKNotificationProviderCancelCallback)(WKNotificationRef notification, const void* _Nullable clientInfo);
typedef void (*WKNotificationProviderDidDestroyNotificationCallback)(WKNotificationRef notification, const void* _Nullable clientInfo);
typedef void (*WKNotificationProviderAddNotificationManagerCallback)(WKNotificationManagerRef manager, const void* _Nullable clientInfo);
typedef void (*WKNotificationProviderRemoveNotificationManagerCallback)(WKNotificationManagerRef manager, const void* _Nullable clientInfo);
typedef WKDictionaryRef _Nullable (*WKNotificationProviderNotificationPermissionsCallback)(const void* _Nullable clientInfo);
typedef void (*WKNotificationProviderClearNotificationsCallback)(WKArrayRef notificationIDs, const void* _Nullable clientInfo);

typedef struct WKNotificationProviderBase {
    int version;
    const void* _Nullable clientInfo;
} WKNotificationProviderBase;

typedef struct WKNotificationProviderV0 {
    WKNotificationProviderBase base;

    // Version 0.
    WKNotificationProviderShowCallback _Nullable show;
    WKNotificationProviderCancelCallback _Nullable cancel;
    WKNotificationProviderDidDestroyNotificationCallback _Nullable didDestroyNotification;
    WKNotificationProviderAddNotificationManagerCallback _Nullable addNotificationManager;
    WKNotificationProviderRemoveNotificationManagerCallback _Nullable removeNotificationManager;
    WKNotificationProviderNotificationPermissionsCallback _Nullable notificationPermissions;
    WKNotificationProviderClearNotificationsCallback _Nullable clearNotifications;
} WKNotificationProviderV0;

// MARK: - Notification managers (WKNotificationManager.h, WKContext.h, WKPage.h)

/// The process pool a page belongs to.
extern WKContextRef WKPageGetContext(WKPageRef page);

/// The pool's manager for page notifications (`new Notification()`).
extern WKNotificationManagerRef WKContextGetNotificationManager(WKContextRef context);

/// The app-wide manager for service worker notifications the data store delegate leaves to WebKit.
extern WKNotificationManagerRef WKNotificationManagerGetSharedServiceWorkerNotificationManager(void);

/// Replaces the manager's provider. The struct is copied; `clientInfo` must outlive the manager's use of it.
extern void WKNotificationManagerSetProvider(WKNotificationManagerRef manager, const WKNotificationProviderBase* _Nullable provider);

/// Fires the notification's `show` event.
extern void WKNotificationManagerProviderDidShowNotification(WKNotificationManagerRef manager, uint64_t notificationID);

/// Fires `click` on a page notification, or `notificationclick` in the service worker for a persistent one.
extern void WKNotificationManagerProviderDidClickNotification(WKNotificationManagerRef manager, uint64_t notificationID);

/// Fires `close` / `notificationclose`. `notificationIDs` holds `WKUInt64Ref` notification IDs.
extern void WKNotificationManagerProviderDidCloseNotifications(WKNotificationManagerRef manager, WKArrayRef notificationIDs);

/// Tells the manager's running web processes the origin's new permission.
extern void WKNotificationManagerProviderDidUpdateNotificationPolicy(WKNotificationManagerRef manager, WKSecurityOriginRef origin, bool allowed);

/// Tells the manager's running web processes the origins are back to `default`. `origins` holds `WKSecurityOriginRef`.
extern void WKNotificationManagerProviderDidRemoveNotificationPolicies(WKNotificationManagerRef manager, WKArrayRef origins);

// MARK: - Notification (WKNotification.h, WKNotificationPrivateMac.h)

enum {
    kWKNotificationAlertDefault = 1 << 0,
    kWKNotificationAlertSilent = 1 << 1,
    kWKNotificationAlertEnabled = 1 << 2
};
typedef uint32_t WKNotificationAlert;

extern WKStringRef _Nullable WKNotificationCopyTitle(WKNotificationRef notification);
extern WKStringRef _Nullable WKNotificationCopyBody(WKNotificationRef notification);
extern WKStringRef _Nullable WKNotificationCopyIconURL(WKNotificationRef notification);
extern WKStringRef _Nullable WKNotificationCopyTag(WKNotificationRef notification);
extern WKStringRef _Nullable WKNotificationCopyLang(WKNotificationRef notification);
extern WKSecurityOriginRef _Nullable WKNotificationGetSecurityOrigin(WKNotificationRef notification);
/// The notification's ID within its manager; the ID the provider callbacks and `…DidClick…` use.
extern uint64_t WKNotificationGetID(WKNotificationRef notification);
/// The data store's identifier for a persistent notification; NULL for the default data store and page notifications.
extern WKStringRef _Nullable WKNotificationCopyDataStoreIdentifier(WKNotificationRef notification);
extern bool WKNotificationGetIsPersistent(WKNotificationRef notification);
extern WKNotificationAlert WKNotificationGetAlert(WKNotificationRef notification);
/// The notification as `-[WKWebsiteDataStore _processPersistentNotificationClick:]` takes it. Property-list values only.
extern NSDictionary * _Nullable WKNotificationCopyDictionaryRepresentation(WKNotificationRef notification) NS_RETURNS_RETAINED;

// MARK: - Values (WKString.h, WKStringCF.h, WKArray.h, WKNumber.h, WKDictionary.h, WKSecurityOriginRef.h, WKType.h)

extern CFStringRef _Nullable WKStringCopyCFString(CFAllocatorRef _Nullable allocator, WKStringRef string) CF_RETURNS_RETAINED;
extern WKStringRef WKStringCreateWithUTF8CString(const char* string);
extern WKArrayRef WKArrayCreate(WKTypeRef _Nonnull * _Nullable values, size_t numberOfValues);
extern WKUInt64Ref WKUInt64Create(uint64_t value);
extern uint64_t WKUInt64GetValue(WKUInt64Ref value);
extern size_t WKArrayGetSize(WKArrayRef array);
extern WKTypeRef _Nullable WKArrayGetItemAtIndex(WKArrayRef array, size_t index);
extern WKBooleanRef WKBooleanCreate(bool value);
extern WKDictionaryRef WKDictionaryCreate(const WKStringRef _Nonnull * _Nullable keys, const WKTypeRef _Nonnull * _Nullable values, size_t numberOfValues);
extern WKSecurityOriginRef WKSecurityOriginCreateFromString(WKStringRef string);
extern WKStringRef WKSecurityOriginCopyToString(WKSecurityOriginRef origin);
extern void WKRelease(WKTypeRef type);

// MARK: - Preferences (WKPreferencesPrivate.h)

@interface WKPreferences (RefraxNotifications)

/// Exposes the `Notification` API to pages. On by default on macOS.
@property (nonatomic, setter=_setNotificationsEnabled:) BOOL _notificationsEnabled API_AVAILABLE(macos(10.13.4));

/// `ServiceWorkerRegistration.showNotification()` and the `notificationclick` / `notificationclose`
/// service worker events. On by default on macOS.
@property (nonatomic, setter=_setNotificationEventEnabled:) BOOL _notificationEventEnabled API_AVAILABLE(macos(13.3));

@end

// MARK: - Data store delegate (_WKWebsiteDataStoreDelegate.h)

/// The subset of WebKit's `_WKWebsiteDataStoreDelegate` Refrax implements. WebKit checks each
/// selector with `respondsToSelector:` when the delegate is assigned.
NS_SWIFT_UI_ACTOR
@protocol _WKWebsiteDataStoreDelegate <NSObject>
@optional

/// Origin string (`https://example.com`) → granted, read when a web process for this store launches.
- (NSDictionary<NSString *, NSNumber *> *)notificationPermissionsForWebsiteDataStore:(WKWebsiteDataStore *)dataStore
    NS_SWIFT_NAME(notificationPermissions(forWebsiteDataStore:));

/// `clients.openWindow(url)` from a service worker. Complete with a web view that is already
/// loading `url` in this data store, or nil to reject the call.
- (void)websiteDataStore:(WKWebsiteDataStore *)dataStore
              openWindow:(NSURL *)url
 fromServiceWorkerOrigin:(WKSecurityOrigin *)serviceWorkerOrigin
       completionHandler:(void (^)(WKWebView * _Nullable newWebView))completionHandler
    NS_SWIFT_NAME(websiteDataStore(_:openWindow:fromServiceWorkerOrigin:completionHandler:));

/// A declarative Web Push notification's default action URL, when the user clicks it.
- (void)websiteDataStore:(WKWebsiteDataStore *)dataStore navigateToNotificationActionURL:(NSURL *)url
    NS_SWIFT_NAME(websiteDataStore(_:navigateToNotificationActionURL:));

@end

// MARK: - Data store (WKWebsiteDataStorePrivate.h)

@interface WKWebsiteDataStore (RefraxNotifications)

/// Weak. WebKit reads which optional methods the delegate implements when it is assigned.
@property (nullable, nonatomic, weak) id<_WKWebsiteDataStoreDelegate> _delegate API_AVAILABLE(macos(10.15));

/// Fires `notificationclick` in the service worker, from a `WKNotificationCopyDictionaryRepresentation`
/// dictionary. Completes with whether a service worker handled it.
- (void)_processPersistentNotificationClick:(NSDictionary *)notificationDictionaryRepresentation
                          completionHandler:(void (^)(bool))completionHandler API_AVAILABLE(macos(13.0))
    NS_SWIFT_NAME(_processPersistentNotificationClick(_:completionHandler:));

@end

NS_ASSUME_NONNULL_END

#endif /* WKNotificationPrivate_h */
