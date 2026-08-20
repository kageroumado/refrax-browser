import Carbon
import Foundation
import WebKit

// MARK: - Editor State Swizzle for macOS AutoFill

/// Provides macOS form field focus detection via method swizzling.
///
/// On iOS, WebKit calls `_WKInputDelegate._webView:didStartInputSession:` when a form field
/// gains focus. On macOS, this delegate method is never called - WebKit only sends a simple
/// boolean `SetEditableElementIsFocused` IPC message.
///
/// This extension swizzles `_web_editorStateDidChange` to detect form field focus on macOS
/// by monitoring secure input state (for password fields) and querying the active element
/// via JavaScript.
///
/// ## Setup
/// Call `WKWebView.installAutoFillSwizzle()` once at app launch.
///
/// ## Architecture
/// 1. `_web_editorStateDidChange` is called by WebKit when editor state changes
/// 2. We check `IsSecureEventInputEnabled()` to detect password field focus
/// 3. We query `document.activeElement` via JavaScript for field details
/// 4. We create a synthetic `_WKFormInputSession` and call the delegate
extension WKWebView {
    // MARK: - Swizzle Installation

    /// Installs the editor state swizzle for macOS autofill detection.
    ///
    /// Call this method once at app launch, typically in `AppDelegate.applicationDidFinishLaunching`.
    ///
    /// - Important: This method is idempotent - calling it multiple times is safe.
    static func installAutoFillSwizzle() {
        EditorStateSwizzle.install()
    }

    /// Handler called when focus moves away from an autofillable field.
    ///
    /// Set this to hide the autofill popover when the field loses focus.
    static var onAutoFillFieldFocusLost: (() -> Void)? {
        get { EditorStateSwizzle.onFocusLost }
        set { EditorStateSwizzle.onFocusLost = newValue }
    }
}

// MARK: - Swizzle Implementation

/// Manages the method swizzle for `_web_editorStateDidChange`.
private enum EditorStateSwizzle {
    /// Whether the swizzle has been installed.
    private static var isInstalled = false

    /// Tracks the previous secure input state to detect changes.
    private static var previousSecureInputState = false

    /// Original implementation pointer.
    private static var originalImplementation: IMP?

    /// Handler called when focus moves away from an autofillable field.
    static var onFocusLost: (() -> Void)?

    /// Installs the swizzle (idempotent).
    static func install() {
        guard !isInstalled else { return }

        guard let originalMethod = class_getInstanceMethod(
            WKWebView.self,
            #selector(WKWebView._web_editorStateDidChange),
        ) else {
            Logger.error("Failed to find _web_editorStateDidChange method", category: Logger.autoFill)
            return
        }

        originalImplementation = method_getImplementation(originalMethod)

        let swizzledBlock: @convention(block) (WKWebView) -> Void = { webView in
            // Call original implementation first
            if let original = originalImplementation {
                typealias OriginalFunction = @convention(c) (AnyObject, Selector) -> Void
                let originalFunc = unsafeBitCast(original, to: OriginalFunction.self)
                originalFunc(webView, #selector(WKWebView._web_editorStateDidChange))
            }

            // Check if secure input state changed (password field focus)
            let currentSecureInputState = WKIsSecureInputEnabled()

            if currentSecureInputState != previousSecureInputState {
                previousSecureInputState = currentSecureInputState

                if currentSecureInputState {
                    // Password field just gained focus
                    handlePasswordFieldFocus(webView: webView)
                } else {
                    // Password field just lost focus
                    handleFieldBlur(webView: webView)
                }
            } else {
                // Secure input didn't change, but editor state did
                // This could be a non-password field focus (email, username, etc.)
                // Query the active element to check
                checkForCredentialFieldFocus(webView: webView)
            }
        }

        let swizzledImplementation = imp_implementationWithBlock(swizzledBlock)
        method_setImplementation(originalMethod, swizzledImplementation)

        isInstalled = true
        Logger.debug("AutoFill editor state swizzle installed", category: Logger.autoFill)
    }

    // MARK: - Focus Handlers

    /// Handles password field gaining focus.
    private static func handlePasswordFieldFocus(webView: WKWebView) {
        guard webView.url?.allowsAutoFill == true else { return }

        queryFocusedElementInfo(webView: webView, expectedType: .password) { elementInfo in
            guard let elementInfo else { return }
            notifyInputDelegate(webView: webView, elementInfo: elementInfo)
        }
    }

    /// Handles password field losing focus.
    private static func handleFieldBlur(webView _: WKWebView) {
        Logger.debug("Password field lost focus", category: Logger.autoFill)
        onFocusLost?()
    }

    /// Checks if a non-password credential field (email/username) gained focus.
    private static func checkForCredentialFieldFocus(webView: WKWebView) {
        guard webView.url?.allowsAutoFill == true else { return }

        queryFocusedElementInfo(webView: webView, expectedType: nil) { elementInfo in
            // No input element focused - focus moved away
            guard let elementInfo else {
                onFocusLost?()
                return
            }

            // Detect field type using all available information including autocomplete
            let fieldType = AutoFillFieldDetector.detectFieldType(
                label: elementInfo.label,
                placeholder: elementInfo.placeholder,
                name: elementInfo.name,
                autocomplete: elementInfo.autocomplete,
                inputType: elementInfo.type,
            )

            // Focus moved to non-autofillable field
            guard fieldType != .none else {
                onFocusLost?()
                return
            }

            notifyInputDelegate(webView: webView, elementInfo: elementInfo)
        }
    }

    // MARK: - Element Query

    /// Queries the focused element's information via JavaScript.
    private static func queryFocusedElementInfo(
        webView: WKWebView,
        expectedType: WKInputType?,
        completion: @escaping (FocusedElementInfoImpl?) -> Void,
    ) {
        let js = """
        (function() {
            const el = document.activeElement;
            if (!el || !['INPUT', 'TEXTAREA'].includes(el.tagName)) {
                return null;
            }
        
            const inputType = el.type ? el.type.toLowerCase() : 'text';
        
            // Find associated label
            let label = null;
            if (el.id) {
                const labelEl = document.querySelector('label[for="' + el.id + '"]');
                if (labelEl) {
                    label = labelEl.textContent.trim();
                }
            }
            if (!label && el.closest('label')) {
                label = el.closest('label').textContent.trim();
            }
        
            // Get aria-label if no label found
            if (!label && el.getAttribute('aria-label')) {
                label = el.getAttribute('aria-label');
            }
        
            // Get autocomplete attribute for additional hints
            const autocomplete = el.getAttribute('autocomplete') || '';
        
            return {
                tagName: el.tagName,
                inputType: inputType,
                name: el.name || null,
                id: el.id || null,
                placeholder: el.placeholder || null,
                label: label,
                value: el.value || '',
                autocomplete: autocomplete,
                isUserInitiated: true
            };
        })();
        """

        // Without-gesture evaluation: this fires on every editor-state change
        // (every focus transition), and a gesture-forced evaluation strips the
        // page's transient user activation when it completes — killing the very
        // click being inspected before the page can spend it on fullscreen,
        // popups, or PiP. The SPI's completion lacks the public API's @MainActor
        // annotation; WebKit still calls it on the main thread.
        nonisolated(unsafe) let completion = completion
        webView._evaluateJavaScriptWithoutUserGesture(js) { result, error in
            nonisolated(unsafe) let result = result
            MainActor.assumeIsolated {
                guard error == nil,
                      let dict = result as? [String: Any],
                      let inputTypeString = dict["inputType"] as? String
                else {
                    completion(nil)
                    return
                }

                let wkInputType = mapInputType(inputTypeString)

                // If we expected a specific type, verify it matches
                if let expectedType, wkInputType != expectedType {
                    completion(nil)
                    return
                }

                let elementInfo = FocusedElementInfoImpl(
                    type: wkInputType,
                    value: dict["value"] as? String,
                    placeholder: dict["placeholder"] as? String,
                    label: dict["label"] as? String,
                    name: dict["name"] as? String,
                    fieldId: dict["id"] as? String,
                    autocomplete: dict["autocomplete"] as? String,
                    isUserInitiated: dict["isUserInitiated"] as? Bool ?? true,
                )

                completion(elementInfo)
            }
        }
    }

    /// Maps HTML input type to WKInputType.
    private static func mapInputType(_ htmlType: String) -> WKInputType {
        switch htmlType.lowercased() {
        case "password": .password
        case "email": .email
        case "tel": .phone
        case "url": .URL
        case "number": .number
        case "search": .search
        case "date": .date
        case "datetime-local": .dateTimeLocal
        case "month": .month
        case "week": .week
        case "time": .time
        case "color": .color
        default: .text
        }
    }

    // MARK: - Delegate Notification

    /// Notifies the input delegate about the focused element.
    private static func notifyInputDelegate(webView: WKWebView, elementInfo: FocusedElementInfoImpl) {
        guard let inputDelegate = webView._inputDelegate() else {
            return
        }

        let inputSession = FormInputSessionImpl(focusedElementInfo: elementInfo)
        inputDelegate._webView?(webView, didStart: inputSession)
    }
}

// MARK: - FocusedElementInfo Implementation

/// Custom implementation of `_WKFocusedElementInfo` for macOS.
///
/// Since macOS WebKit doesn't provide focused element info natively,
/// we create this from JavaScript query results.
final class FocusedElementInfoImpl: NSObject, _WKFocusedElementInfo {
    let type: WKInputType
    let value: String?
    let placeholder: String?
    let label: String?
    let isUserInitiated: Bool

    /// Additional properties not in the protocol but useful for autofill.
    let name: String?
    let fieldId: String?
    let autocomplete: String?

    init(
        type: WKInputType,
        value: String?,
        placeholder: String?,
        label: String?,
        name: String?,
        fieldId: String?,
        autocomplete: String?,
        isUserInitiated: Bool,
    ) {
        self.type = type
        self.value = value
        self.placeholder = placeholder
        self.label = label
        self.name = name
        self.fieldId = fieldId
        self.autocomplete = autocomplete
        self.isUserInitiated = isUserInitiated
        super.init()
    }

    // Protocol requirements
    var userObject: (any NSSecureCoding & NSObjectProtocol)? { nil }
    var frame: WKFrameInfo? { nil }
}

// MARK: - FormInputSession Implementation

/// Custom implementation of `_WKFormInputSession` for macOS.
final class FormInputSessionImpl: NSObject, _WKFormInputSession {
    private let _focusedElementInfo: FocusedElementInfoImpl
    private var _isValid = true

    init(focusedElementInfo: FocusedElementInfoImpl) {
        self._focusedElementInfo = focusedElementInfo
        super.init()
    }

    // Protocol requirements
    var isValid: Bool { _isValid }
    var userObject: (any NSSecureCoding & NSObjectProtocol)? { nil }
    var focusedElementInfo: (any _WKFocusedElementInfo)? { _focusedElementInfo }

    /// Marks the session as invalid (called when the element loses focus).
    func invalidate() {
        _isValid = false
    }
}
