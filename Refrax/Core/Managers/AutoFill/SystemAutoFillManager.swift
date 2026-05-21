import AppKit
import Foundation
import os

/// Manager for requesting autofill data from system services (Passwords, Contacts, Credit Cards).
///
/// This manager provides integration with macOS system autofill services, allowing users to use
/// credentials, contacts, and credit cards stored in the system Keychain/iCloud.
///
/// ## Overview
///
/// `SystemAutoFillManager` uses AppKit's private `_handleInsertFrom*Command:` APIs
/// to invoke the same pickers that appear in the "AutoFill → …" context menus.
/// This approach works without requiring a valid code signature, unlike `ASAuthorizationController`.
///
/// The system uses RemoteTextInput (RTI) to communicate with a privileged daemon that has
/// keychain access. Domain filtering is achieved by swizzling `RTIDocumentTraits.encodeWithCoder:`
/// to inject associated domains before the traits are serialized and sent to the remote service.
///
/// ## Supported Pickers
///
/// - **Passwords**: Stored credentials from Keychain/iCloud Keychain
/// - **Credit Cards**: Payment cards stored in Safari/iCloud
/// - **Contacts**: Contact information from Contacts.app
///
/// ## Usage
///
/// ```swift
/// let manager = SystemAutoFillManager()
/// manager.showPasswordPicker(forDomains: ["github.com"])   // Filtered by domain
/// manager.showCreditCardPicker()                            // Credit Cards…
/// manager.showContactsPicker()                              // Contacts…
/// ```
///
/// - Note: This uses the responder chain to trigger system pickers.
///   Data is inserted directly into the focused text field by the system.
final class SystemAutoFillManager: NSObject {
    // MARK: - Singleton

    static let shared = SystemAutoFillManager()

    // MARK: - Selector Constants

    private enum Selectors {
        static let passwords = "_handleInsertFromPasswordsCommand:"
        static let creditCards = "_handleInsertFromCreditCardsCommand:"
        static let contacts = "_handleInsertFromContactsCommand:"
    }

    // MARK: - Private State

    private static let injectedDomainsLock = OSAllocatedUnfairLock<[String]>(initialState: [])
    private static var isSwizzled = false
    private static var originalEncodeMethod: Method?
    private static var swizzledEncodeMethod: Method?

    // MARK: - Initialization

    override private init() {
        super.init()
        loadRemoteTextInputFramework()
    }

    // MARK: - Public API

    /// Shows the system Passwords picker filtered by the specified domains.
    ///
    /// This triggers the same UI as the "AutoFill → Passwords…" context menu item.
    /// The system will handle Touch ID / password authentication and insert the
    /// selected credential into the currently focused text field.
    ///
    /// - Parameter domains: Array of domains to filter passwords by.
    ///   Only passwords matching these domains will be shown in the picker.
    ///
    /// - Important: A text field must be focused for this to work. The system checks
    ///   for a valid text input context before showing the picker.
    func showPasswordPicker(forDomains domains: [String]) {
        guard !domains.isEmpty else {
            Logger.warning("showPasswordPicker called with empty domains", category: Logger.autoFill)
            sendAutoFillAction(Selectors.passwords, name: "Passwords")
            return
        }

        presentPasswordPickerWithDomainFilter(domains)
    }

    /// Shows the system Credit Cards picker.
    ///
    /// This triggers the same UI as the "AutoFill → Credit Cards…" context menu item.
    /// The system will handle Touch ID / password authentication and insert the
    /// selected card details into the currently focused text field.
    func showCreditCardPicker() {
        sendAutoFillAction(Selectors.creditCards, name: "Credit Cards")
    }

    /// Shows the system Contacts picker.
    ///
    /// This triggers the same UI as the "AutoFill → Contacts…" context menu item.
    /// The system will insert the selected contact information into the currently focused text field.
    func showContactsPicker() {
        sendAutoFillAction(Selectors.contacts, name: "Contacts")
    }

    // MARK: - Private Implementation

    /// Loads the RemoteTextInput private framework.
    private func loadRemoteTextInputFramework() {
        let rtiPath = "/System/Library/PrivateFrameworks/RemoteTextInput.framework/RemoteTextInput"
        if dlopen(rtiPath, RTLD_NOW) == nil {
            if let error = dlerror() {
                Logger.warning(
                    "Could not load RemoteTextInput framework: \(String(cString: error))",
                    category: Logger.autoFill,
                )
            }
        }
    }

    /// Sends an autofill action through the responder chain.
    private func sendAutoFillAction(_ selectorString: String, name: String) {
        let selector = Selector(selectorString)
        let sent = NSApp.sendAction(selector, to: nil, from: nil)

        if sent {
            Logger.debug("Triggered system \(name) picker via responder chain", category: Logger.autoFill)
        } else {
            Logger.warning("No responder handled \(selectorString)", category: Logger.autoFill)
        }
    }

    /// Presents the password picker with domain filtering by temporarily swizzling RTIDocumentTraits.
    ///
    /// The system serializes RTIDocumentTraits via `encodeWithCoder:` before sending to the
    /// privileged password daemon. By swizzling this method, we can inject our domains
    /// right before serialization.
    private func presentPasswordPickerWithDomainFilter(_ domains: [String]) {
        Self.injectedDomainsLock.withLock { state in
            state = domains
        }

        guard installSwizzleIfNeeded() else {
            Self.injectedDomainsLock.withLock { state in
                state.removeAll()
            }
            sendAutoFillAction(Selectors.passwords, name: "Passwords")
            return
        }

        sendAutoFillAction(Selectors.passwords, name: "Passwords")
    }

    /// Installs the encodeWithCoder: swizzle on RTIDocumentTraits if not already installed.
    /// Returns true if swizzle is active, false if it could not be installed.
    private func installSwizzleIfNeeded() -> Bool {
        if Self.isSwizzled {
            return true
        }

        guard let traitsClass = NSClassFromString("RTIDocumentTraits") else {
            Logger.error("RTIDocumentTraits class not found", category: Logger.autoFill)
            return false
        }

        let encodeSelector = NSSelectorFromString("encodeWithCoder:")
        let swizzledEncodeSelector = #selector(Self.swizzled_encodeWithCoder(_:))

        guard let encodeMethod = class_getInstanceMethod(traitsClass, encodeSelector),
              let swizzledEncodeMethod = class_getInstanceMethod(Self.self, swizzledEncodeSelector)
        else {
            Logger.error("Could not get methods for swizzling", category: Logger.autoFill)
            return false
        }

        // Add our swizzled method to RTIDocumentTraits class
        let didAdd = class_addMethod(
            traitsClass,
            swizzledEncodeSelector,
            method_getImplementation(swizzledEncodeMethod),
            method_getTypeEncoding(swizzledEncodeMethod),
        )

        guard didAdd,
              let addedMethod = class_getInstanceMethod(traitsClass, swizzledEncodeSelector)
        else {
            Logger.error("Could not add swizzled method to RTIDocumentTraits", category: Logger.autoFill)
            return false
        }

        // Swap implementations
        method_exchangeImplementations(encodeMethod, addedMethod)

        Self.isSwizzled = true
        Self.originalEncodeMethod = encodeMethod
        Self.swizzledEncodeMethod = addedMethod

        Logger.debug("Installed RTIDocumentTraits.encodeWithCoder: swizzle", category: Logger.autoFill)
        return true
    }

    /// Swizzled encodeWithCoder: that injects associated domains before encoding.
    ///
    /// When the system serializes RTIDocumentTraits to send to the password daemon,
    /// this method intercepts to inject our desired domains for filtering.
    /// Domains are cleared immediately after injection since they're only needed once per XPC call.
    @objc
    private func swizzled_encodeWithCoder(_ coder: NSCoder) {
        // Inject our domains into the traits object before encoding, then clear immediately
        let domainsToInject = Self.injectedDomainsLock.withLock { state -> [String] in
            guard !state.isEmpty else { return [] }
            let domains = state
            state.removeAll()
            return domains
        }

        if !domainsToInject.isEmpty {
            let setDomainsSel = NSSelectorFromString("setAssociatedDomains:")
            if responds(to: setDomainsSel) {
                _ = perform(setDomainsSel, with: domainsToInject as NSArray)
            }
        }

        // Call original implementation (now at swizzled selector due to exchange)
        let originalSel = #selector(Self.swizzled_encodeWithCoder(_:))
        if responds(to: originalSel) {
            perform(originalSel, with: coder)
        }
    }
}
