@preconcurrency import LocalAuthentication
import SwiftUI

/// An overlay view displayed when a locked space requires authentication.
///
/// This view implements the Passwords-app style lock UI pattern:
/// - Full-window blur over all content
/// - App icon with TouchID badge in bottom-right
/// - Title showing "{space.name} Is Locked"
/// - Password field as primary input (always visible)
/// - LocalAuthenticationView for inline Touch ID at bottom
/// - Inline error display
///
/// ## Layout Strategy
///
/// The Touch ID view (LocalAuthenticationView) is placed at the bottom of the
/// authentication section. This is intentional: the view can render as empty/void
/// in certain states (e.g., after cancellation, on devices without Touch ID).
/// By placing it at the bottom, any empty rendering doesn't create a visual gap
/// in the center of the UI.
///
/// ## Authentication Flow
///
/// 1. Password field is shown as primary authentication method
/// 2. LocalAuthenticationView provides inline Touch ID below
/// 3. Password submission validates via OpenDirectory (no system dialog)
/// 4. Errors are displayed inline above the Touch ID section
///
/// ## Usage
///
/// ```swift
/// ZStack {
///     MainContentView()
///
///     if needsAuth {
///         LockedSpaceOverlayView(space: space)
///     }
/// }
/// ```
struct LockedSpaceOverlayView: View {
    @Environment(BrowserState.self) private var browserState

    let space: Space

    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var error: String?
    @FocusState private var isPasswordFieldFocused: Bool

    /// Whether Touch ID hardware is available on this system.
    private var isTouchIDAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    // MARK: - Layout

    private enum Layout {
        static let appIconSize: CGFloat = 80
        static let badgeSize: CGFloat = 28
        static let badgeOffset: CGFloat = 4
        static let contentSpacing: CGFloat = 20
        static let sectionSpacing: CGFloat = 12
        static let textFieldWidth: CGFloat = 180
        static let containerPadding: CGFloat = 40
        static let dividerWidth: CGFloat = 200
    }

    // MARK: - Body

    var body: some View {
        // Use Rectangle + contentShape to receive hit events (Color.clear doesn't receive hits).
        // The content is overlaid on top and centered, but doesn't impose size requirements.
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .overlay {
                fullWindowBlur
            }
            .overlay {
                lockContent
            }
    }

    // MARK: - Components

    private var fullWindowBlur: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private var lockContent: some View {
        VStack(spacing: Layout.contentSpacing) {
            appIconWithBadge
            titleSection
            authenticationSection
        }
        .padding(Layout.containerPadding)
    }

    private var appIconWithBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Layout.appIconSize, height: Layout.appIconSize)

            if isTouchIDAvailable {
                touchIDBadge
            }
        }
    }

    private var touchIDBadge: some View {
        Image(systemName: "touchid")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Layout.badgeSize, height: Layout.badgeSize)
            .background(.thickMaterial, in: Circle())
            .overlay(Circle().stroke(.quaternary, lineWidth: 0.5))
            .offset(x: Layout.badgeOffset, y: Layout.badgeOffset)
    }

    private var titleSection: some View {
        VStack(spacing: 8) {
            Text("\(space.name) Is Locked")
                .font(.title2.bold())

            Text(
                isTouchIDAvailable
                    ? "Touch ID or enter the password for the user “\(NSFullUserName())” to unlock."
                    : "Enter the password for the user “\(NSFullUserName())” to unlock.",
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Authentication Section

    /// Authentication UI with password field primary, Touch ID at bottom.
    ///
    /// Touch ID is placed at the bottom because LocalAuthenticationView can render
    /// as empty in certain states. This prevents a visual gap in the center.
    private var authenticationSection: some View {
        VStack(spacing: Layout.sectionSpacing) {
            // Password field (primary - always visible)
            passwordSection

            // Error message
            errorSection

            // Touch ID section (only shown if hardware is available)
            if isTouchIDAvailable {
                orDivider
                touchIDView
            }
        }
    }

    private var passwordSection: some View {
        SecureField(text: $password) {
            // This is the only way to center text, since TextField filters all
            // view modifiers or spacers
            Text("          Enter password")
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: Layout.textFieldWidth)
        .focused($isPasswordFieldFocused)
        .onSubmit(authenticateWithPassword)
        .disabled(isAuthenticating)
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Layout.textFieldWidth)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.quaternary)
                .frame(width: (Layout.dividerWidth - 30) / 2, height: 1)

            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(.quaternary)
                .frame(width: (Layout.dividerWidth - 30) / 2, height: 1)
        }
    }

    private var touchIDView: some View {
        LocalAuthenticationView(
            "Unlock with Touch ID",
            reason: Text("Unlock \"\(space.name)\" space"),
        ) { result in
            handleTouchIDResult(result)
        }
        .controlSize(.large)
    }

    // MARK: - Touch ID Handler

    /// Handles the result from LocalAuthenticationView.
    private func handleTouchIDResult(_ result: Result<Void, any Error>) {
        switch result {
        case .success:
            // LocalAuthenticationView succeeded - mark space as unlocked
            browserState.spaceLockManager.markUnlockedFromLocalAuthenticationView(space: space)

        case let .failure(authError):
            if let laError = authError as? LAError {
                switch laError.code {
                case .userCancel:
                    // User cancelled - focus password field
                    isPasswordFieldFocused = true
                case .biometryLockout:
                    withAnimation {
                        error = "Touch ID is locked. Please use your password."
                    }
                    isPasswordFieldFocused = true
                case .biometryNotAvailable, .biometryNotEnrolled:
                    // Don't show error - Touch ID view will be empty, password is primary
                    isPasswordFieldFocused = true
                default:
                    withAnimation {
                        error = "Authentication failed. Please try again."
                    }
                    isPasswordFieldFocused = true
                }
            } else {
                withAnimation {
                    error = "Authentication failed. Please try again."
                }
                isPasswordFieldFocused = true
            }
        }
    }

    // MARK: - Password Authentication

    /// Authenticates using the password entered by the user.
    ///
    /// Uses OpenDirectory to validate the password against the current user's
    /// macOS account without showing any system dialog.
    private func authenticateWithPassword() {
        guard !password.isEmpty else { return }

        isAuthenticating = true
        error = nil

        let result = browserState.spaceLockManager.authenticateWithPassword(password, for: space)

        isAuthenticating = false

        switch result {
        case .success:
            password = ""
        case .failed:
            withAnimation {
                error = "Incorrect password. Please try again."
            }
            password = ""
        case .cancelled, .unavailable:
            // These shouldn't happen with password auth
            break
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview(traits: .modifier(RefraxPreviewModifier())) {
        LockedSpaceOverlayView(space: Space(
            id: UUID(),
            name: "Work",
            iconName: "briefcase.fill",
            colorHex: GroupColor.steel.rawValue,
            position: 0,
        ))
    }
#endif
