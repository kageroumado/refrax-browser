@import WebKit;

#import "WKNotificationPrivate.h"

@class RFXWebNotificationProvider;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

/// A notification WebKit asked the provider to show, copied out of the `WKNotificationRef`
/// that is valid only during the callback.
NS_SWIFT_UI_ACTOR
@interface RFXWebNotification : NSObject

/// WebKit's ID for the notification within its manager.
@property (nonatomic, readonly) uint64_t identifier;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *body;
/// Empty when the page gave no tag.
@property (nonatomic, readonly, copy) NSString *tag;
/// The security origin string, e.g. `https://example.com`.
@property (nonatomic, readonly, copy) NSString *origin;
@property (nonatomic, readonly, copy, nullable) NSURL *iconURL;
/// The data store a persistent notification belongs to; nil for the default data store.
@property (nonatomic, readonly, copy, nullable) NSUUID *dataStoreIdentifier;
/// Shown by a service worker (`registration.showNotification`).
@property (nonatomic, readonly, getter=isPersistent) BOOL persistent;
/// The page asked for `silent: true`.
@property (nonatomic, readonly, getter=isSilent) BOOL silent;
/// The page that showed it; NULL for a persistent notification.
@property (nonatomic, readonly, nullable) WKPageRef page;
/// The persistent notification as `-[WKWebsiteDataStore _processPersistentNotificationClick:]` takes it.
@property (nonatomic, readonly, copy, nullable) NSDictionary *dictionaryRepresentation;

- (instancetype)init NS_UNAVAILABLE;

@end

/// Receives a notification manager's provider callbacks, on the main thread.
NS_SWIFT_UI_ACTOR
@protocol RFXWebNotificationProviderDelegate <NSObject>

- (void)notificationProvider:(RFXWebNotificationProvider *)provider showNotification:(RFXWebNotification *)notification
    NS_SWIFT_NAME(notificationProvider(_:show:));

/// The page called `notification.close()`.
- (void)notificationProvider:(RFXWebNotificationProvider *)provider cancelNotification:(uint64_t)identifier
    NS_SWIFT_NAME(notificationProvider(_:cancel:));

/// WebKit forgot the notification; its ID is no longer valid.
- (void)notificationProvider:(RFXWebNotificationProvider *)provider didDestroyNotification:(uint64_t)identifier
    NS_SWIFT_NAME(notificationProvider(_:didDestroy:));

/// The page's notifications are gone (the page closed or navigated away).
- (void)notificationProvider:(RFXWebNotificationProvider *)provider clearNotifications:(NSArray<NSNumber *> *)identifiers
    NS_SWIFT_NAME(notificationProvider(_:clear:));

/// Origin string → granted, for web processes the manager's pool launches.
- (NSDictionary<NSString *, NSNumber *> *)notificationPermissionsForProvider:(RFXWebNotificationProvider *)provider
    NS_SWIFT_NAME(notificationPermissions(for:));

/// The manager's process pool was destroyed; the provider no longer receives or sends anything.
- (void)notificationProviderDidDetach:(RFXWebNotificationProvider *)provider
    NS_SWIFT_NAME(notificationProviderDidDetach(_:));

@end

/// Refrax's provider on one WebKit notification manager: a process pool's, for page
/// notifications, or the shared service worker manager.
///
/// Holds the manager's C provider and forwards its callbacks to `delegate`. The provider must
/// stay alive while installed: WebKit keeps an unretained pointer to it.
NS_SWIFT_UI_ACTOR
@interface RFXWebNotificationProvider : NSObject

/// Identifies the manager of `webView`'s process pool, for finding an installed provider.
+ (NSUInteger)managerKeyForWebView:(WKWebView *)webView NS_SWIFT_NAME(managerKey(for:));

/// A provider for the manager of `webView`'s process pool.
- (instancetype)initWithWebView:(WKWebView *)webView NS_SWIFT_NAME(init(webView:));

/// A provider for the app-wide service worker notification manager.
+ (instancetype)serviceWorkerProvider NS_SWIFT_NAME(serviceWorkerProvider());

- (instancetype)init NS_UNAVAILABLE;

/// Identifies the manager this provider serves.
@property (nonatomic, readonly) NSUInteger managerKey;

/// Whether the manager still exists.
@property (nonatomic, readonly, getter=isAttached) BOOL attached;

@property (nonatomic, weak, nullable) id<RFXWebNotificationProviderDelegate> delegate;

/// Installs the provider on its manager, replacing WebKit's default provider.
- (void)install;

/// Fires the notification's `show` event.
- (void)didShowNotification:(uint64_t)identifier NS_SWIFT_NAME(didShow(_:));

/// Fires `click`, or `notificationclick` for a persistent notification.
- (void)didClickNotification:(uint64_t)identifier NS_SWIFT_NAME(didClick(_:));

/// Fires `close`, or `notificationclose` for a persistent notification.
- (void)didCloseNotifications:(NSArray<NSNumber *> *)identifiers NS_SWIFT_NAME(didClose(_:));

/// Tells the pool's running web processes an origin's new permission.
- (void)updatePermission:(BOOL)allowed forOrigin:(NSString *)origin NS_SWIFT_NAME(updatePermission(_:for:));

/// Returns the origins to `default` in the pool's running web processes.
- (void)removePermissionsForOrigins:(NSArray<NSString *> *)origins NS_SWIFT_NAME(removePermissions(for:));

@end

NS_HEADER_AUDIT_END(nullability, sendability)
