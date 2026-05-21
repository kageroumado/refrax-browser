/**
 * AutoFillUIPrivate.h
 * Refrax Browser
 *
 * Private headers for AutoFillUI.framework
 *
 * This framework handles the system password autofill UI on macOS.
 * It uses RTIDocumentTraits/RTIDocumentState from RemoteTextInput
 * to configure the autofill context including domain filtering.
 *
 * ## Key Discovery
 * - `RTIDocumentTraits.associatedDomains` controls domain filtering
 * - `AFUIPasswordsController` can present a password picker with domain context
 * - Setting `explicitAutoFillMode = YES` indicates explicit user invocation
 */

#ifndef AutoFillUIPrivate_h
#define AutoFillUIPrivate_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - RemoteTextInput Framework Types

/// Document traits that describe the text input context.
/// Includes domain info, app identity, and autofill configuration.
@interface RTIDocumentTraits : NSObject <NSCopying, NSSecureCoding>

@property (nonatomic) int processId;
@property (copy, nonatomic, nullable) NSString *appId;
@property (copy, nonatomic, nullable) NSString *bundleId;
@property (copy, nonatomic, nullable) NSString *appName;
@property (copy, nonatomic, nullable) NSString *localizedAppName;

/// Associated domains for credential filtering.
/// Set this to the website's domain to filter passwords.
@property (retain, nonatomic, nullable) NSArray<NSString *> *associatedDomains;

@property (copy, nonatomic, nullable) NSObject<NSCopying, NSSecureCoding> *responderId;
@property (copy, nonatomic, nullable) NSString *sceneID;
@property (nonatomic) unsigned long long entityID;
@property (nonatomic) unsigned int contextID;
@property (copy, nonatomic, nullable) NSString *sceneExclusivityIdentifier;

@property (copy, nonatomic, nullable) NSString *title;
@property (copy, nonatomic, nullable) NSString *prompt;

/// Autofill mode indicator.
@property (nonatomic) unsigned long long autofillMode;
@property (nonatomic) unsigned long long autofillSubMode;

/// Additional autofill context dictionary.
@property (retain, nonatomic, nullable) NSDictionary *autofillContext;

/// Whether this is an explicit autofill invocation (user clicked "Passwords...").
@property (nonatomic) BOOL explicitAutoFillMode;

/// Password rules for generation.
@property (copy, nonatomic, nullable) NSString *passwordRules;

/// Additional user info.
@property (retain, nonatomic, nullable) NSDictionary *userInfo;

@end

/// Document state describing the current text input state.
/// Includes caret position, selection, and geometry for popover positioning.
@interface RTIDocumentState : NSObject <NSSecureCoding, NSCopying>

@property (nonatomic) BOOL hasText;
@property (nonatomic) CGRect caretRectInWindow;
@property (nonatomic) CGRect firstSelectionRectInWindow;
@property (nonatomic) CGRect clientFrameInWindow;
@property (nonatomic) BOOL scrolling;

+ (instancetype)documentStateWithRequest:(nullable id)request;

@end

// MARK: - AutoFillUI Framework Types

/// Protocol for receiving password picker callbacks.
@protocol AFUIPasswordPickerDelegate <NSObject>

- (void)passwordsController:(id)controller fillPassword:(NSString *)password;
- (void)passwordsController:(id)controller fillUsername:(NSString *)username;
- (void)passwordsController:(id)controller fillText:(NSString *)text;
- (void)passwordsController:(id)controller fillVerificationCode:(NSString *)code;
- (void)passwordsController:(id)controller selectedCredential:(id)credential;
- (void)passwordsControllerDidCancel:(id)controller;

@end

/// Controller for the password picker UI.
/// Uses RTIDocumentTraits.associatedDomains for filtering.
@interface AFUIPasswordsController : NSObject

@property (weak, nonatomic, nullable) id<AFUIPasswordPickerDelegate> passwordPickerDelegate;

- (instancetype)initWithDocumentTraits:(RTIDocumentTraits *)traits;

/// Creates a password picker view controller.
- (NSViewController *)makePasswordPickerViewController;

/// Presents the password picker from a view controller.
- (void)presentPasswordPickerFromViewController:(NSViewController *)controller
                     didFinishAuthenticationBlock:(nullable void (^)(void))block;

@end

/// Main autofill popover view controller.
/// Can present passwords, contacts, or credit cards.
@interface AFUIAutoFillPopoverViewController : NSViewController

@property (retain, nonatomic, nullable) RTIDocumentTraits *documentTraits;
@property (retain, nonatomic, nullable) RTIDocumentState *documentState;

/// Presents as a popover from a window.
+ (nullable instancetype)presentAsPopoverFromWindow:(NSWindow *)window
                                     documentTraits:(RTIDocumentTraits *)traits
                                      documentState:(RTIDocumentState *)state
                             keyboardOutputHandler:(void (^)(NSDictionary * _Nullable output))handler;

+ (nullable instancetype)presentAsPopoverFromWindow:(NSWindow *)window
                                     documentTraits:(RTIDocumentTraits *)traits
                                      documentState:(RTIDocumentState *)state
                            textOperationsHandler:(void (^)(id _Nullable operations))handler;

- (instancetype)initWithDocumentTraits:(RTIDocumentTraits *)traits
                         documentState:(RTIDocumentState *)state
                keyboardOutputHandler:(void (^)(NSDictionary * _Nullable output))handler;

- (instancetype)initWithDocumentTraits:(RTIDocumentTraits *)traits
                         documentState:(RTIDocumentState *)state
               textOperationsHandler:(void (^)(id _Nullable operations))handler;

/// Present the passwords view.
- (void)presentPasswords;

/// Check if there are suggestions available.
- (BOOL)hasSuggestions;

@end

NS_ASSUME_NONNULL_END

#endif /* AutoFillUIPrivate_h */
