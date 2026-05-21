/**
 * WKWebAuthenticationPrivate.h
 * Refrax Browser
 *
 * Private WebKit APIs for WebAuthentication (FIDO2/Passkeys) management.
 *
 * This header provides access to the passkey credential store, enabling:
 * - Listing all stored passkeys
 * - Deleting credentials
 * - Exporting/importing credentials
 * - Checking platform authenticator availability
 *
 * ## Credential Storage
 * WebKit stores passkeys in the system keychain. These credentials are:
 * - Protected by Touch ID / Face ID / password
 * - Synced via iCloud Keychain (if enabled)
 * - Accessible across devices
 *
 * ## Thread Safety
 * All APIs must be called on the main thread.
 *
 * ## Source Reference
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKWebAuthenticationPanel.h
 *
 * Last verified: WebKit trunk (December 2024)
 */

#import <WebKit/WebKit.h>

// Forward declaration for Local Authentication
@class LAContext;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Credential Dictionary Keys

/**
 * Keys for credential information dictionaries returned by
 * `getAllLocalAuthenticatorCredentials` and related methods.
 *
 * ## Usage
 * @code
 * NSDictionary *credential = credentials.firstObject;
 * NSString *name = credential[_WKLocalAuthenticatorCredentialNameKey];
 * NSData *credentialID = credential[_WKLocalAuthenticatorCredentialIDKey];
 * NSString *rpID = credential[_WKLocalAuthenticatorCredentialRelyingPartyIDKey];
 * @endcode
 */

/** The user-visible name for the credential (from user.name in WebAuthn). */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialNameKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** The user-visible display name (from user.displayName in WebAuthn). */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialDisplayNameKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** The credential ID as NSData (unique identifier). */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialIDKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** The relying party ID (typically the website domain). */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialRelyingPartyIDKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** The credential creation date as NSDate. */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialCreationDateKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** The last modification date as NSDate. */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialLastModificationDateKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** The credential group identifier (for organizing credentials). */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialGroupKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** Whether the credential syncs via iCloud Keychain (NSNumber boolean). */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialSynchronizableKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** The user handle as NSData (from user.id in WebAuthn). */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialUserHandleKey
    API_AVAILABLE(macos(12.0), ios(15.0));

/** The last used date as NSDate. */
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialLastUsedDateKey
    API_AVAILABLE(macos(12.0), ios(15.0));

#pragma mark - _WKWebAuthenticationPanel

/**
 * WebAuthentication (FIDO2/Passkeys) panel controller.
 *
 * Provides access to WebAuthn functionality:
 * - Query stored passkeys
 * - Delete credentials
 * - Export/import credentials
 * - Check platform authenticator availability
 *
 * ## Usage - List All Passkeys
 * @code
 * NSArray *credentials = [_WKWebAuthenticationPanel getAllLocalAuthenticatorCredentials];
 * for (NSDictionary *credential in credentials) {
 *     NSString *name = credential[_WKLocalAuthenticatorCredentialNameKey];
 *     NSString *rpID = credential[_WKLocalAuthenticatorCredentialRelyingPartyIDKey];
 *     NSLog(@"Passkey: %@ for %@", name, rpID);
 * }
 * @endcode
 *
 * ## Usage - Delete a Passkey
 * @code
 * NSData *credentialID = credential[_WKLocalAuthenticatorCredentialIDKey];
 * [_WKWebAuthenticationPanel deleteLocalAuthenticatorCredentialWithID:credentialID];
 * @endcode
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKWebAuthenticationPanel.h
 *
 * ## Availability
 * macOS 10.15.4+, iOS 13.4+
 */
API_AVAILABLE(macos(10.15.4), ios(13.4))
@interface _WKWebAuthenticationPanel : NSObject

#pragma mark - Initialization

- (instancetype)init;

#pragma mark - Credential Query (Class Methods)

/**
 * Returns all locally stored authenticator credentials.
 *
 * @return Array of dictionaries containing credential information.
 *
 * ## Dictionary Keys
 * - `_WKLocalAuthenticatorCredentialNameKey`: User name
 * - `_WKLocalAuthenticatorCredentialDisplayNameKey`: Display name
 * - `_WKLocalAuthenticatorCredentialIDKey`: Credential ID (NSData)
 * - `_WKLocalAuthenticatorCredentialRelyingPartyIDKey`: Website domain
 * - `_WKLocalAuthenticatorCredentialCreationDateKey`: Creation date
 * - `_WKLocalAuthenticatorCredentialLastUsedDateKey`: Last used date
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
+ (NSArray<NSDictionary *> *)getAllLocalAuthenticatorCredentials
    API_AVAILABLE(macos(12.0), ios(15.0));

/**
 * Returns credentials for a specific relying party (website).
 *
 * @param rpID The relying party ID (typically the website domain, e.g., "example.com").
 * @return Array of credential dictionaries for that relying party.
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
+ (NSArray<NSDictionary *> *)getAllLocalAuthenticatorCredentialsWithRPID:(NSString *)rpID
    API_AVAILABLE(macos(13.0), ios(16.0));

/**
 * Returns credentials matching a specific credential ID.
 *
 * @param credentialID The credential ID to search for.
 * @return Array of matching credential dictionaries (usually 0 or 1).
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
+ (NSArray<NSDictionary *> *)getAllLocalAuthenticatorCredentialsWithCredentialID:(NSData *)credentialID
    API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - Credential Deletion (Class Methods)

/**
 * Deletes a credential by its ID.
 *
 * @param credentialID The credential ID to delete.
 *
 * ## Warning
 * This permanently deletes the passkey. The user will need to create
 * a new passkey for the affected website.
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
+ (void)deleteLocalAuthenticatorCredentialWithID:(NSData *)credentialID
    API_AVAILABLE(macos(12.0), ios(15.0));

/**
 * Deletes a credential by group and ID.
 *
 * @param group The credential group (can be nil for ungrouped credentials).
 * @param credentialID The credential ID to delete.
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
+ (void)deleteLocalAuthenticatorCredentialWithGroupAndID:(nullable NSString *)group
                                              credential:(NSData *)credentialID
    API_AVAILABLE(macos(12.0), ios(15.0));

/**
 * Clears ALL locally stored authenticator credentials.
 *
 * ## Warning
 * This permanently deletes ALL stored passkeys. Use with extreme caution.
 * Consider requiring user confirmation before calling.
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
+ (void)clearAllLocalAuthenticatorCredentials
    API_AVAILABLE(macos(12.0), ios(15.0));

#pragma mark - Credential Modification (Class Methods)

/**
 * Updates the display name for a credential.
 *
 * @param group The credential group (can be nil).
 * @param credentialID The credential ID.
 * @param displayName The new display name.
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
+ (void)setDisplayNameForLocalCredentialWithGroupAndID:(nullable NSString *)group
                                            credential:(NSData *)credentialID
                                           displayName:(NSString *)displayName
    API_AVAILABLE(macos(13.0), ios(16.0));

/**
 * Updates the name for a credential.
 *
 * @param group The credential group (can be nil).
 * @param credentialID The credential ID.
 * @param name The new name.
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
+ (void)setNameForLocalCredentialWithGroupAndID:(nullable NSString *)group
                                     credential:(NSData *)credentialID
                                           name:(NSString *)name
    API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - Credential Export/Import (Class Methods)

/**
 * Exports a credential to a portable format.
 *
 * @param credentialID The credential ID to export.
 * @param error On failure, contains error information.
 * @return The exported credential data, or nil on failure.
 *
 * ## Security
 * The exported data is still encrypted and requires authentication
 * to use on import.
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
+ (nullable NSData *)exportLocalAuthenticatorCredentialWithID:(NSData *)credentialID
                                                        error:(NSError **)error
    API_AVAILABLE(macos(13.0), ios(16.0));

/**
 * Imports a credential from exported data.
 *
 * @param credentialBlob The exported credential data.
 * @param error On failure, contains error information.
 * @return The imported credential ID, or nil on failure.
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
+ (nullable NSData *)importLocalAuthenticatorCredential:(NSData *)credentialBlob
                                                  error:(NSError **)error
    API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - Platform Authenticator (Class Methods)

/**
 * Whether a user-verifying platform authenticator is available.
 *
 * Returns YES if the device has Touch ID, Face ID, or similar biometric
 * authentication available for passkey operations.
 *
 * ## Usage
 * @code
 * if ([_WKWebAuthenticationPanel isUserVerifyingPlatformAuthenticatorAvailable]) {
 *     [self enablePasskeyFeatures];
 * }
 * @endcode
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
+ (BOOL)isUserVerifyingPlatformAuthenticatorAvailable
    API_AVAILABLE(macos(12.0), ios(15.0));

#pragma mark - Instance Methods

/**
 * Cancels the current authentication operation.
 *
 * Call this when the user dismisses the authentication UI without completing.
 */
- (void)cancel;

#pragma mark - Properties

/** The relying party ID for the current operation. */
@property (nonatomic, readonly, copy, nullable) NSString *relyingPartyID;

/** The available transports for authentication (USB, NFC, internal, etc.). */
@property (nonatomic, readonly, copy, nullable) NSSet *transports;

/** The user name for the current operation. */
@property (nonatomic, readonly, copy, nullable) NSString *userName;

@end

NS_ASSUME_NONNULL_END
