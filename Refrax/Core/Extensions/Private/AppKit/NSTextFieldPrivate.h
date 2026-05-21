/**
 * NSTextFieldPrivate.h
 * Refrax Browser
 *
 * Private NSTextField APIs for advanced text field customization.
 *
 * These APIs are particularly useful for address bars and search fields,
 * enabling control over password autofill, suggestions, and appearance.
 *
 * ## Key Features
 *
 * - **Password Autofill**: Control password autofill behavior
 * - **Suggestions**: Text suggestions and autocomplete
 * - **Writing Tools**: macOS Tahoe AI writing features
 * - **Appearance**: Border shape, tint, and style configuration
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSTextFieldPrivate_h
#define NSTextFieldPrivate_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Border Shape

/**
 * Border shape styles for text fields.
 *
 * Controls the visual appearance of the text field's border.
 */
typedef NS_ENUM(NSInteger, NSTextFieldBorderShape) {
    /** Standard rectangular border */
    NSTextFieldBorderShapeRectangle = 0,
    /** Rounded rectangular border (capsule-like) */
    NSTextFieldBorderShapeRoundedRect = 1,
    /** Circular/pill-shaped border */
    NSTextFieldBorderShapeCapsule = 2
};

#pragma mark - Focus Ring Animation

/**
 * Focus ring animation types for text fields.
 */
typedef NS_ENUM(NSInteger, NSTextFieldFocusRingAnimationType) {
    /** Default focus ring animation */
    NSTextFieldFocusRingAnimationTypeDefault = 0,
    /** No focus ring animation */
    NSTextFieldFocusRingAnimationTypeNone = 1,
    /** Immediate focus ring (no animation) */
    NSTextFieldFocusRingAnimationTypeImmediate = 2
};

@interface NSTextField (RefraxPrivate)

#pragma mark - Password Autofill

/**
 * Whether password autofill is enabled for this text field.
 *
 * When YES (default for secure text fields), the system password
 * autofill UI can appear for this field.
 *
 * Set to NO to disable password autofill suggestions, useful when
 * the field is not intended for password entry despite being secure.
 *
 * ## Example
 * ```objc
 * // Disable password autofill for a PIN entry field
 * secureTextField._passwordAutofillEnabled = NO;
 * ```
 */
@property (nonatomic, getter=_isPasswordAutofillEnabled) BOOL _passwordAutofillEnabled;

#pragma mark - Appearance

/**
 * The border shape style for the text field.
 *
 * Controls the visual shape of the text field's border.
 * See `NSTextFieldBorderShape` for available options.
 */
@property (nonatomic) NSTextFieldBorderShape borderShape;

/**
 * The focus ring animation type.
 *
 * Controls how the focus ring animates when the field gains focus.
 */
@property (nonatomic) NSTextFieldFocusRingAnimationType _focusRingAnimationType;

/**
 * The tint configuration for sidebar contexts.
 *
 * Used when the text field appears in a sidebar to coordinate
 * with the sidebar's tint color.
 */
@property (retain, nullable) NSTintConfiguration *_sidebarTintConfiguration;

/**
 * Whether the text field is inside a form context.
 *
 * Affects autofill behavior and field grouping.
 */
@property (nonatomic) BOOL _insideFormContext;

#pragma mark - Suggestions

/**
 * The delegate for text suggestions.
 *
 * Implement this delegate to provide custom suggestions
 * for the text field's autocomplete functionality.
 */
@property (nonatomic, weak, nullable) id suggestionsDelegate;

/**
 * Whether text suggestions are currently being shown.
 */
@property (readonly, nonatomic) BOOL _isShowingTextSuggestions;

/**
 * Whether the search suggestions first responder override is enabled.
 */
@property (readonly, nonatomic) BOOL _searchSuggestionsFirstResponderOverrideEnabled;

/**
 * Resumes autocomplete after it was paused.
 *
 * Call this to re-enable autocomplete suggestions after
 * programmatically pausing them.
 */
- (void)_resumeAutocomplete;

#pragma mark - Writing Tools (macOS Tahoe)

/**
 * Whether Writing Tools (AI writing assistance) is allowed.
 *
 * When YES, the system's AI writing tools can be used with this field.
 * New in macOS Tahoe.
 */
@property (nonatomic) BOOL allowsWritingTools;

/**
 * Whether the Writing Tools affordance (UI indicator) is shown.
 *
 * When YES, a visual indicator shows that Writing Tools are available.
 * New in macOS Tahoe.
 */
@property (nonatomic) BOOL allowsWritingToolsAffordance;

#pragma mark - Content Type

/**
 * The semantic content type for the text field.
 *
 * Used for autofill and keyboard suggestions. Common values include:
 * - `"username"`: User name field
 * - `"password"`: Password field
 * - `"URL"`: URL/address field
 * - `"emailAddress"`: Email field
 * - `"telephoneNumber"`: Phone number field
 */
@property (copy, nullable) NSString *contentType;

#pragma mark - Layout

/**
 * Language-aware padding insets for the text field.
 *
 * Returns insets that account for the current language's
 * typographic requirements (e.g., taller line height for
 * languages with diacritics or non-Latin scripts).
 */
@property (readonly) NSEdgeInsets languageAwareOutsets;

/**
 * Whether content-aware typesetting language detection is enabled.
 *
 * When YES, the text field automatically detects the language
 * of the content and adjusts typography accordingly.
 */
@property (nonatomic) BOOL _wantsContentAwareTypesettingLanguage;

#pragma mark - Actions

/**
 * The action to perform when a validation error occurs.
 *
 * Set this to handle validation failures in the text field.
 */
@property (nullable) SEL errorAction;

/**
 * Sets the error action selector.
 *
 * @param action The selector to call on validation error.
 */
- (void)setErrorAction:(nullable SEL)action;

@end

NS_ASSUME_NONNULL_END

#endif /* NSTextFieldPrivate_h */
