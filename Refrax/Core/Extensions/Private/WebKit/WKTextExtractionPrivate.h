/**
 * WKTextExtractionPrivate.h
 * Refrax Browser
 *
 * Private APIs for WebKit's text extraction system.
 *
 * This header declares the internal types and methods for structured page
 * content extraction via `_WKTextExtraction`. These APIs provide access to
 * WebKit's native content tree, enabling visibility-aware, Shadow DOM-aware,
 * and accessibility-rich page extraction without JavaScript DOM walking.
 *
 * ## Contents
 * - _WKTextExtractionConfiguration (public API — config for extraction)
 * - _WKTextExtractionResult (public API — formatted text output)
 * - _WKTextExtractionInteraction (public API — native element interaction)
 * - WKTextExtractionItem hierarchy (internal — structured content tree)
 * - WKWebView extraction methods (internal — invocation points)
 * - WKPreferences _textExtractionEnabled (internal — feature gate)
 *
 * ## Thread Safety
 * All APIs must be called on the main thread.
 *
 * ## Source References
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKTextExtraction.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKTextExtractionInternal.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h
 *
 * Last verified: WebKit trunk (February 2026)
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Public API Types

#pragma mark - Filter Options

typedef NS_OPTIONS(NSUInteger, _WKTextExtractionFilterOptions) {
    _WKTextExtractionFilterNone = 0,
    _WKTextExtractionFilterTextRecognition = 1 << 0,
    _WKTextExtractionFilterClassifier = 1 << 1,
    _WKTextExtractionFilterRules = 1 << 2,
    _WKTextExtractionFilterAll = NSUIntegerMax,
};

#pragma mark - Node Identifier Inclusion

typedef NS_ENUM(NSInteger, _WKTextExtractionNodeIdentifierInclusion) {
    _WKTextExtractionNodeIdentifierInclusionNone = 0,
    _WKTextExtractionNodeIdentifierInclusionEditableOnly,
    _WKTextExtractionNodeIdentifierInclusionInteractive
};

#pragma mark - Output Format

typedef NS_ENUM(NSInteger, _WKTextExtractionOutputFormat) {
    _WKTextExtractionOutputFormatTextTree = 0,
    _WKTextExtractionOutputFormatHTML,
    _WKTextExtractionOutputFormatMarkdown,
};

#pragma mark - Configuration

@interface _WKTextExtractionConfiguration : NSObject

@property (nonatomic, class, copy, readonly) _WKTextExtractionConfiguration *configurationForVisibleTextOnly NS_SWIFT_NAME(visibleTextOnly);

/// Output format: `.textTree`, `.HTML`, or `.markdown`.
@property (nonatomic) _WKTextExtractionOutputFormat outputFormat;

/// Constrain extraction to elements intersecting this rect (web view coordinates).
/// Default is `CGRectNull` (all elements).
@property (nonatomic) CGRect targetRect;

/// Include URL attribute values (href, src, etc.). Default: YES.
@property (nonatomic) BOOL includeURLs;

/// Include bounding rects for all text nodes. Default: YES.
@property (nonatomic) BOOL includeRects;

/// Policy for which nodes get unique identifiers.
/// `.interactive` assigns IDs to buttons, links, and other interactive elements.
@property (nonatomic) _WKTextExtractionNodeIdentifierInclusion nodeIdentifierInclusion;

/// Include event listener information. Default: YES.
@property (nonatomic) BOOL includeEventListeners;

/// Include ARIA attributes (role, aria-label, etc.). Default: YES.
@property (nonatomic) BOOL includeAccessibilityAttributes;

/// Include text in AutoFill-modified form controls. Default: YES.
@property (nonatomic) BOOL includeTextInAutoFilledControls;

/// Max words per paragraph; truncated with ellipsis. Default: NSUIntegerMax.
@property (nonatomic) NSUInteger maxWordsPerParagraph;

/// Filters to apply during extraction. Default: all filters.
@property (nonatomic) _WKTextExtractionFilterOptions filterOptions;

/// Shorten extracted URLs. Default: NO.
@property (nonatomic) BOOL shortenURLs;

/// Ignores transparent or nearly-transparent subtrees. Default: NO.
@property (nonatomic) BOOL skipNearlyTransparentContent;

/// Merge adjacent text runs into paragraphs. Default: NO.
@property (nonatomic) BOOL mergeParagraphs;

@end

#pragma mark - Result

@interface _WKTextExtractionResult : NSObject

@property (nonatomic, readonly) NSString *textContent;
@property (nonatomic, readonly) BOOL filteredOutAnyText;
@property (nonatomic, readonly) NSDictionary<NSString *, NSURL *> *shortenedURLs;

@end

#pragma mark - Interaction Action

typedef NS_ENUM(NSInteger, _WKTextExtractionAction) {
    _WKTextExtractionActionClick,
    _WKTextExtractionActionSelectText,
    _WKTextExtractionActionSelectMenuItem,
    _WKTextExtractionActionTextInput,
    _WKTextExtractionActionKeyPress,
    _WKTextExtractionActionHighlightText,
    _WKTextExtractionActionScrollBy
};

#pragma mark - Interaction

@interface _WKTextExtractionInteraction : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAction:(_WKTextExtractionAction)action NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) _WKTextExtractionAction action;
@property (nonatomic, copy, nullable) NSString *nodeIdentifier;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic) BOOL replaceAll;
@property (nonatomic) BOOL scrollToVisible;
@property (nonatomic) CGSize scrollDelta;
@property (nonatomic) CGPoint location;

@end

#pragma mark - Interaction Result

@interface _WKTextExtractionInteractionResult : NSObject

@property (nonatomic, readonly, nullable) NSError *error;

@end

// MARK: - Internal Types (WKTextExtractionItem hierarchy)

#pragma mark - Container Type

typedef NS_ENUM(NSInteger, WKTextExtractionContainer) {
    WKTextExtractionContainerRoot,
    WKTextExtractionContainerViewportConstrained,
    WKTextExtractionContainerList,
    WKTextExtractionContainerListItem,
    WKTextExtractionContainerBlockQuote,
    WKTextExtractionContainerArticle,
    WKTextExtractionContainerSection,
    WKTextExtractionContainerNav,
    WKTextExtractionContainerButton,
    WKTextExtractionContainerCanvas,
    WKTextExtractionContainerSubscript,
    WKTextExtractionContainerSuperscript,
    WKTextExtractionContainerGeneric
};

#pragma mark - Event Listener Types

typedef NS_OPTIONS(NSUInteger, WKTextExtractionEventListenerTypes) {
    WKTextExtractionEventListenerTypeNone      = 0,
    WKTextExtractionEventListenerTypeClick     = 1 << 0,
    WKTextExtractionEventListenerTypeHover     = 1 << 1,
    WKTextExtractionEventListenerTypeTouch     = 1 << 2,
    WKTextExtractionEventListenerTypeWheel     = 1 << 3,
    WKTextExtractionEventListenerTypeKeyboard  = 1 << 4,
};

#pragma mark - Editable Type

typedef NS_ENUM(NSInteger, WKTextExtractionEditableType) {
    WKTextExtractionEditablePlainTextOnly,
    WKTextExtractionEditableRichText,
};

#pragma mark - Item Hierarchy

@interface WKTextExtractionItem : NSObject
@property (nonatomic, readonly) NSArray<WKTextExtractionItem *> *children;
@property (nonatomic, readonly) CGRect rectInWebView;
@property (nonatomic, readonly) WKTextExtractionEventListenerTypes eventListeners;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *ariaAttributes;
@property (nonatomic, readonly) NSString *accessibilityRole;
@property (nonatomic, readonly, nullable) NSString *nodeIdentifier;
@end

@interface WKTextExtractionContainerItem : WKTextExtractionItem
@property (nonatomic, readonly) WKTextExtractionContainer container;
@end

@interface WKTextExtractionTextItem : WKTextExtractionItem
@property (nonatomic, copy) NSString *content;
@property (nonatomic) NSRange selectedRange;
@end

@interface WKTextExtractionLinkItem : WKTextExtractionItem
@property (nonatomic, readonly) NSString *target;
@property (nonatomic, readonly, nullable) NSURL *url;
@end

@interface WKTextExtractionImageItem : WKTextExtractionItem
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *altText;
@end

// WKTextExtractionFormItem is defined in WebKit source but not yet shipped.
// Detected at runtime via NSStringFromClass in PageContentExtractor.

@interface WKTextExtractionTextFormControlItem : WKTextExtractionItem
@property (nonatomic, readonly) NSString *label;
@property (nonatomic, readonly) NSString *placeholder;
@property (nonatomic, readonly, getter=isSecure) BOOL secure;
@property (nonatomic, readonly, getter=isFocused) BOOL focused;
@property (nonatomic, readonly) NSString *controlType;
@property (nonatomic, readonly) NSString *autocomplete;
@property (nonatomic, readonly, getter=isReadonly) BOOL readonly;
@property (nonatomic, readonly, getter=isDisabled) BOOL disabled;
@property (nonatomic, readonly, getter=isChecked) BOOL checked;
@end

@interface WKTextExtractionScrollableItem : WKTextExtractionItem
@property (nonatomic, readonly) CGSize contentSize;
@end

@interface WKTextExtractionSelectItem : WKTextExtractionItem
@property (nonatomic, readonly) NSArray<NSString *> *selectedValues;
@property (nonatomic, readonly) BOOL supportsMultiple;
@end

// WKTextExtractionIFrameItem is defined in WebKit source but not yet shipped.
// Detected at runtime via NSStringFromClass in PageContentExtractor.

@interface WKTextExtractionContentEditableItem : WKTextExtractionItem
@property (nonatomic, readonly) WKTextExtractionEditableType contentEditableType;
@property (nonatomic, readonly, getter=isFocused) BOOL focused;
@end

// MARK: - WKWebView Text Extraction Methods

#pragma mark - WKWebView (WKTextExtraction)

@interface WKWebView (WKTextExtraction)

/// Extracts a structured content tree from the web view.
///
/// Returns a `WKTextExtractionItem` tree representing the page's content,
/// with children, bounding rects, event listeners, ARIA attributes, and
/// node identifiers for interactive elements.
- (void)_requestTextExtraction:(_WKTextExtractionConfiguration *)configuration
             completionHandler:(void (^)(WKTextExtractionItem * _Nullable))completionHandler;

/// Extracts pre-formatted debug text from the web view.
- (void)_debugTextWithConfiguration:(_WKTextExtractionConfiguration *)configuration
                  completionHandler:(void (^)(NSString *))completionHandler
    NS_SWIFT_NAME(_debugText(with:completionHandler:));

/// Extracts debug text with result metadata.
- (void)_extractDebugTextWithConfiguration:(_WKTextExtractionConfiguration *)configuration
                         completionHandler:(void (^)(_WKTextExtractionResult *))completionHandler
    NS_SWIFT_NAME(_extractDebugText(with:completionHandler:));

/// Performs a native interaction on a page element.
///
/// Uses `nodeIdentifier` from extracted items to target elements, enabling
/// click, type, scroll, and other actions without JavaScript.
- (void)_performInteraction:(_WKTextExtractionInteraction *)interaction
          completionHandler:(void (^)(_WKTextExtractionInteractionResult *))completionHandler
    NS_SWIFT_NAME(_performInteraction(_:completionHandler:));

@end

// MARK: - WKPreferences Text Extraction

#pragma mark - WKPreferences (WKTextExtraction)

@interface WKPreferences (WKTextExtraction)

/// Whether text extraction is enabled for the web view.
///
/// Must be set to YES before using `_requestTextExtraction:` or
/// `_debugTextWithConfiguration:`. Required for native content tree access.
///
/// Availability: macOS 15.0+, iOS 18.0+
@property (nonatomic, setter=_setTextExtractionEnabled:) BOOL _textExtractionEnabled;

@end

NS_ASSUME_NONNULL_END
