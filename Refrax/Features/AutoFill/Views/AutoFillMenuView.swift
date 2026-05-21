@preconcurrency import LocalAuthentication
import SwiftUI

/// Menu-style view that displays auto-fill suggestions matching Safari's design.
///
/// Uses Liquid Glass design with:
/// - Glass effect background
/// - 8px inner padding with concentric corner radii
/// - Credential rows from local storage with key icon
/// - "Other Passwords for [domain]..." when more credentials exist than displayed
/// - "Passwords..." option to open the system Passwords app
struct AutoFillMenuView: View {
    @Environment(AutoFillState.self) private var autoFillState
    @Environment(WindowState.self) private var windowState

    let context: AutoFillContext

    /// Whether the user has authenticated for this autofill session.
    ///
    /// Only relevant when `context.requireAuthForAutoFill` is true.
    /// Credentials are gated behind inline Touch ID until this is set.
    @State private var isAutoFillAuthenticated = false

    private var menuShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Constants.outerCornerRadius)
    }

    private var hasMoreCredentials: Bool {
        context.credentials.count > Constants.maxVisibleCredentials
    }

    var body: some View {
        VStack(spacing: Constants.itemSpacing) {
            switch context.fieldType {
            case .credential:
                credentialContent
            case .creditCard:
                creditCardContent
            case .contact:
                contactContent
            case .oneTimeCode:
                passwordsAppRow
            }
        }
        .padding(Constants.contentPadding)
        .frame(width: Constants.menuWidth)
        .onHover { hovering in
            // Block web view events when hovering over autofill overlay
            // to prevent cursor changes and click passthrough
            windowState.webViewsShouldIgnoreAllEvents = hovering
            if hovering {
                NSCursor.arrow.set()
            }
        }
        .glassEffect(in: menuShape)
        .overlay {
            menuShape
                .stroke(.secondary.opacity(0.7), lineWidth: 1)
                .shadow(color: .secondary.opacity(0.25), radius: 3, x: 0, y: 1)
                .shadow(color: .secondary.opacity(0.15), radius: 2, x: 0, y: 0)
        }
    }

    // MARK: - Credential Content

    @ViewBuilder
    private var credentialContent: some View {
        // systemOnly mode: just show system picker
        if context.autoFillMode == .systemOnly {
            // Only show Passwords app picker on login forms or for non-password fields
            if context.isLoginForm || !context.isPasswordField {
                passwordsAppRow
            }
        } else {
            // builtIn mode: full autofill experience
            // Password field: show generate/fill options based on form type
            if context.isPasswordField {
                if context.isLoginForm {
                    // Login form: show fill options only if we have a recently generated password
                    loginPasswordOptions
                } else {
                    // Registration form: show password generation options
                    registrationPasswordOptions
                }
            }

            // Show saved credentials ONLY on login forms
            if context.isLoginForm {
                if context.requireAuthForAutoFill, !isAutoFillAuthenticated {
                    // Gate: show inline Touch ID before revealing credentials
                    autoFillAuthGate
                } else {
                    ForEach(context.credentials.prefix(Constants.maxVisibleCredentials)) { credential in
                        AutoFillCredentialItemView(
                            credential: credential,
                            showTouchIDIcon: false,
                        ) {
                            selectCredential(credential)
                        }
                    }
                }

                // Show "Other Passwords for [domain]..." only if there are more credentials
                if hasMoreCredentials {
                    AutoFillTextItemView(title: otherPasswordsTitle) {
                        // TODO: Expand to show full list of credentials
                    }
                }

                // Show option to use system Passwords app ONLY on login forms
                passwordsAppRow
            }
        }
    }

    /// Password options shown on login forms (fill existing generated password).
    @ViewBuilder
    private var loginPasswordOptions: some View {
        // Show "Fill Password Again" if we have a recently generated password
        if let recentPassword = context.recentlyGeneratedPassword {
            AutoFillGeneratedPasswordItemView(
                password: recentPassword,
                title: "Fill Password Again",
                action: { fillGeneratedPassword(recentPassword) },
            )
        }
    }

    /// Password options shown on registration forms (generate new password).
    @ViewBuilder
    private var registrationPasswordOptions: some View {
        // Show "Fill Password Again" if we have a recently generated password
        if let recentPassword = context.recentlyGeneratedPassword {
            AutoFillGeneratedPasswordItemView(
                password: recentPassword,
                title: "Fill Password Again",
                action: { fillGeneratedPassword(recentPassword) },
            )
        }

        // Show "Suggest New Password" only for the primary password field, NOT confirm fields
        if !context.isConfirmPasswordField {
            AutoFillSuggestPasswordItemView {
                suggestNewPassword()
            }
        }
    }

    private var otherPasswordsTitle: String {
        if let host = context.url.host {
            let displayHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return "Other Passwords for \(displayHost)…"
        }
        return "Other Passwords…"
    }

    private var passwordsAppRow: some View {
        AutoFillPasswordsAppItemView(
            isLoading: autoFillState.isRequestingSystemAutoFill,
            action: requestSystemPasswords,
        )
        .disabled(autoFillState.isRequestingSystemAutoFill)
    }

    // MARK: - Credit Card Content

    private var creditCardContent: some View {
        AutoFillPasswordsAppItemView(
            title: "Autofill Credit Card…",
            isLoading: autoFillState.isRequestingSystemAutoFill,
            action: requestSystemCreditCards,
        )
        .disabled(autoFillState.isRequestingSystemAutoFill)
    }

    // MARK: - Contact Content

    private var contactContent: some View {
        AutoFillTextItemView(title: "Autofill Contact Info…") {
            requestSystemContacts()
        }
        .disabled(autoFillState.isRequestingSystemAutoFill)
    }

    // MARK: - Auth Gate

    /// Compact inline Touch ID gate shown in the autofill popover.
    ///
    /// Uses `LocalAuthenticationView` for inline biometric authentication
    /// (same as the Passwords window) — no system popup dialog.
    private var autoFillAuthGate: some View {
        VStack(spacing: 6) {
            Text("Authenticate to AutoFill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            LocalAuthenticationView(
                "Unlock with Touch ID",
                reason: Text("AutoFill saved password"),
            ) { result in
                if case .success = result {
                    isAutoFillAuthenticated = true
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func selectCredential(_ credential: PasswordsManager.StoredCredential) {
        autoFillState.onCredentialSelected?(credential)
    }

    private func requestSystemPasswords() {
        autoFillState.onSystemPasswordsRequested?()
    }

    private func requestSystemCreditCards() {
        autoFillState.onSystemCreditCardsRequested?()
    }

    private func requestSystemContacts() {
        autoFillState.onSystemContactsRequested?()
    }

    private func suggestNewPassword() {
        autoFillState.onSuggestNewPassword?(
            context.fieldId,
            context.usernameFieldId,
        )
    }

    private func fillGeneratedPassword(_ password: String) {
        autoFillState.onFillGeneratedPassword?(
            password,
            context.fieldId,
            context.usernameFieldId,
        )
    }

    // MARK: - Constants

    private enum Constants {
        static let menuWidth: CGFloat = 300
        static let maxVisibleCredentials = 3
        static let outerCornerRadius: CGFloat = 14
        static let contentPadding: CGFloat = 8
        static let itemSpacing: CGFloat = 2
    }
}

// MARK: - Credential Item View

/// Individual credential row from local storage with key icon, username, domain, and optional Touch ID.
private struct AutoFillCredentialItemView: View {
    let credential: PasswordsManager.StoredCredential
    var showTouchIDIcon: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.contentSpacing) {
                keyIcon
                credentialInfo
                Spacer(minLength: 0)
                if showTouchIDIcon {
                    touchIdIcon
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Constants.selectionCornerRadius)
                    .fill(isHovered ? Color.appAccentColor : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Constants.selectionCornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .white : .primary)
        .onHover { isHovered = $0 }
    }

    private var keyIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Constants.iconCornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Constants.iconGradientTop, Constants.iconGradientBottom],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .frame(width: Constants.iconSize, height: Constants.iconSize)

            Image(systemName: "key.fill")
                .font(.system(size: Constants.keyIconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var credentialInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(credential.username)
                .font(.system(size: Constants.primaryFontSize))
                .lineLimit(1)

            Text(credential.domain)
                .font(.system(size: Constants.secondaryFontSize))
                .foregroundStyle(isHovered ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
        }
    }

    private var touchIdIcon: some View {
        Image(systemName: "touchid")
            .font(.system(size: Constants.touchIdSize))
            .foregroundStyle(isHovered ? .white.opacity(0.8) : .secondary)
    }

    private enum Constants {
        static let contentSpacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
        static let selectionCornerRadius: CGFloat = 6
        static let iconSize: CGFloat = 32
        static let iconCornerRadius: CGFloat = 7
        static let keyIconSize: CGFloat = 14
        static let primaryFontSize: CGFloat = 13
        static let secondaryFontSize: CGFloat = 11
        static let touchIdSize: CGFloat = 18
        static let iconGradientTop = Color(red: 0.3, green: 0.6, blue: 1.0)
        static let iconGradientBottom = Color(red: 0.2, green: 0.4, blue: 0.9)
    }
}

// MARK: - Text Item View

/// Text-only action row (e.g., "Other Passwords for github.com...").
private struct AutoFillTextItemView: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: Constants.fontSize))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Constants.selectionCornerRadius)
                    .fill(isHovered ? Color.appAccentColor : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Constants.selectionCornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .white : .primary)
        .onHover { isHovered = $0 }
    }

    private enum Constants {
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
        static let selectionCornerRadius: CGFloat = 6
        static let fontSize: CGFloat = 13
    }
}

// MARK: - Passwords App Item View

/// Action row with Passwords app icon for opening system Passwords app.
private struct AutoFillPasswordsAppItemView: View {
    var title: String = "Passwords…"
    var isLoading: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.contentSpacing) {
                passwordsAppIcon

                Text(title)
                    .font(.system(size: Constants.fontSize))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Constants.selectionCornerRadius)
                    .fill(isHovered ? Color.appAccentColor : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Constants.selectionCornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .white : .primary)
        .onHover { isHovered = $0 }
    }

    private var passwordsAppIcon: some View {
        Group {
            if let appIcon = Self.cachedPasswordsAppIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Constants.appIconSize, height: Constants.appIconSize)
            } else {
                // Fallback icon
                Image(systemName: "key.fill")
                    .font(.system(size: Constants.fallbackIconSize))
                    .frame(width: Constants.appIconSize, height: Constants.appIconSize)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Cache the Passwords app icon to avoid repeated lookups
    private static let cachedPasswordsAppIcon: NSImage? = {
        let workspace = NSWorkspace.shared
        if let passwordsURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
            return workspace.icon(forFile: passwordsURL.path)
        }
        return nil
    }()

    private enum Constants {
        static let contentSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
        static let selectionCornerRadius: CGFloat = 6
        static let fontSize: CGFloat = 13
        static let appIconSize: CGFloat = 20
        static let fallbackIconSize: CGFloat = 14
    }
}

// MARK: - Suggest Password Item View

/// Action row for "Suggest New Password" option.
private struct AutoFillSuggestPasswordItemView: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.contentSpacing) {
                suggestIcon

                Text("Suggest New Password…")
                    .font(.system(size: Constants.fontSize))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Constants.selectionCornerRadius)
                    .fill(isHovered ? Color.appAccentColor : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Constants.selectionCornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .white : .primary)
        .onHover { isHovered = $0 }
    }

    private var suggestIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Constants.iconCornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Constants.iconGradientTop, Constants.iconGradientBottom],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .frame(width: Constants.iconSize, height: Constants.iconSize)

            Image(systemName: "wand.and.stars")
                .font(.system(size: Constants.wandIconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private enum Constants {
        static let contentSpacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
        static let selectionCornerRadius: CGFloat = 6
        static let iconSize: CGFloat = 32
        static let iconCornerRadius: CGFloat = 7
        static let wandIconSize: CGFloat = 14
        static let fontSize: CGFloat = 13
        static let iconGradientTop = Color(red: 0.6, green: 0.4, blue: 0.9)
        static let iconGradientBottom = Color(red: 0.5, green: 0.3, blue: 0.8)
    }
}

// MARK: - Generated Password Item View

/// Action row for filling a recently generated password.
private struct AutoFillGeneratedPasswordItemView: View {
    let password: String
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.contentSpacing) {
                generatedIcon

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: Constants.primaryFontSize))
                        .lineLimit(1)

                    Text(password)
                        .font(.system(size: Constants.secondaryFontSize, design: .monospaced))
                        .foregroundStyle(isHovered ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Constants.selectionCornerRadius)
                    .fill(isHovered ? Color.appAccentColor : Color.clear),
            )
            .contentShape(RoundedRectangle(cornerRadius: Constants.selectionCornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .white : .primary)
        .onHover { isHovered = $0 }
    }

    private var generatedIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Constants.iconCornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Constants.iconGradientTop, Constants.iconGradientBottom],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .frame(width: Constants.iconSize, height: Constants.iconSize)

            Image(systemName: "arrow.clockwise")
                .font(.system(size: Constants.refreshIconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private enum Constants {
        static let contentSpacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 6
        static let selectionCornerRadius: CGFloat = 6
        static let iconSize: CGFloat = 32
        static let iconCornerRadius: CGFloat = 7
        static let refreshIconSize: CGFloat = 14
        static let primaryFontSize: CGFloat = 13
        static let secondaryFontSize: CGFloat = 11
        static let iconGradientTop = Color(red: 0.3, green: 0.7, blue: 0.4)
        static let iconGradientBottom = Color(red: 0.2, green: 0.6, blue: 0.3)
    }
}

// MARK: - Previews

#Preview("Credentials with list", traits: .modifier(RefraxPreviewModifier())) {
    let credentials = [
        PasswordsManager.StoredCredential(
            domain: "github.com",
            username: "05-deeds.oculars@icloud.com",
            password: "password123",
        ),
        PasswordsManager.StoredCredential(
            domain: "github.com",
            username: "developer@company.com",
            password: "anotherpass",
        ),
    ]

    let context = AutoFillContext(
        fieldType: .credential,
        credentials: credentials,
        rect: .zero,
        fieldId: "password",
        usernameFieldId: "email",
        url: URL.staticRequired("https://github.com"),
    )

    return AutoFillMenuView(context: context)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Many credentials (shows 'Other Passwords')", traits: .modifier(RefraxPreviewModifier())) {
    let credentials = [
        PasswordsManager.StoredCredential(domain: "github.com", username: "user1@icloud.com", password: "pass1"),
        PasswordsManager.StoredCredential(domain: "github.com", username: "user2@icloud.com", password: "pass2"),
        PasswordsManager.StoredCredential(domain: "github.com", username: "user3@icloud.com", password: "pass3"),
        PasswordsManager.StoredCredential(domain: "github.com", username: "user4@icloud.com", password: "pass4"),
    ]

    let context = AutoFillContext(
        fieldType: .credential,
        credentials: credentials,
        rect: .zero,
        fieldId: "password",
        usernameFieldId: "email",
        url: URL.staticRequired("https://github.com"),
    )

    return AutoFillMenuView(context: context)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Registration form (no saved credentials shown)", traits: .modifier(RefraxPreviewModifier())) {
    let context = AutoFillContext(
        fieldType: .credential,
        isPasswordField: true,
        isLoginForm: false,
        credentials: [],
        rect: .zero,
        fieldId: "password",
        usernameFieldId: "email",
        url: URL.staticRequired("https://github.com"),
    )

    return AutoFillMenuView(context: context)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Password field with recent password", traits: .modifier(RefraxPreviewModifier())) {
    let context = AutoFillContext(
        fieldType: .credential,
        isPasswordField: true,
        credentials: [],
        recentlyGeneratedPassword: "hojceg-pakgop-Dyrdi7",
        rect: .zero,
        fieldId: "password",
        usernameFieldId: "email",
        url: URL.staticRequired("https://github.com"),
    )

    return AutoFillMenuView(context: context)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Credentials - System only", traits: .modifier(RefraxPreviewModifier())) {
    let context = AutoFillContext(
        fieldType: .credential,
        credentials: [],
        rect: .zero,
        fieldId: "password",
        usernameFieldId: "email",
        url: URL.staticRequired("https://example.com"),
    )

    return AutoFillMenuView(context: context)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Credit Card", traits: .modifier(RefraxPreviewModifier())) {
    let context = AutoFillContext(
        fieldType: .creditCard,
        rect: .zero,
        fieldId: "cc-number",
        usernameFieldId: nil,
        url: URL.staticRequired("https://example.com"),
    )

    return AutoFillMenuView(context: context)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}

#Preview("Contact", traits: .modifier(RefraxPreviewModifier())) {
    let context = AutoFillContext(
        fieldType: .contact,
        rect: .zero,
        fieldId: "address",
        usernameFieldId: nil,
        url: URL.staticRequired("https://example.com"),
    )

    return AutoFillMenuView(context: context)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
