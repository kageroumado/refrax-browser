@preconcurrency import LocalAuthentication
import SwiftUI

/// Main view for the Passwords window.
///
/// Displays an authentication overlay on launch that requires TouchID or
/// the user's macOS password. Once authenticated, shows the searchable
/// list of stored credentials.
///
/// This follows the pattern from `LockedSpaceOverlayView` for authentication UI.
struct PasswordsView: View {
    @Environment(PasswordsManager.self) private var passwordsManager

    @State private var isAuthenticated = false
    @State private var selectedCredential: PasswordsManager.StoredCredential?

    var body: some View {
        ZStack {
            // Main content (visible after authentication)
            if isAuthenticated {
                authenticatedContent
            }

            // Authentication overlay (visible until authenticated)
            if !isAuthenticated {
                PasswordsAuthOverlay(isAuthenticated: $isAuthenticated)
            }
        }
    }

    // MARK: - Authenticated Content

    private var authenticatedContent: some View {
        NavigationSplitView {
            PasswordsListView(selectedCredential: $selectedCredential)
                .environment(passwordsManager)
        } detail: {
            if let credential = selectedCredential {
                PasswordDetailView(credential: credential)
                    .environment(passwordsManager)
            } else {
                noSelectionView
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var noSelectionView: some View {
        ContentUnavailableView {
            Label("No Password Selected", systemImage: "key.fill")
        } description: {
            Text("Select a password from the sidebar to view its details.")
        }
    }
}

// MARK: - Authentication Overlay

/// Full-window overlay requiring TouchID or password to view credentials.
///
/// Mirrors the pattern from `LockedSpaceOverlayView`:
/// - Full-window blur
/// - App icon with TouchID badge
/// - Password field as primary input
/// - LocalAuthenticationView for inline TouchID
struct PasswordsAuthOverlay: View {
    @Binding var isAuthenticated: Bool

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
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .overlay {
                fullWindowBlur
            }
            .overlay {
                lockContent
            }
            .onAppear {
                // Auto-focus password field if Touch ID not available
                if !isTouchIDAvailable {
                    isPasswordFieldFocused = true
                }
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
            Text("Passwords Is Locked")
                .font(.title2.bold())

            Text(
                isTouchIDAvailable
                    ? "Touch ID or enter the password for the user \"\(NSFullUserName())\" to unlock."
                    : "Enter the password for the user \"\(NSFullUserName())\" to unlock.",
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Authentication Section

    private var authenticationSection: some View {
        VStack(spacing: Layout.sectionSpacing) {
            passwordSection
            errorSection

            if isTouchIDAvailable {
                orDivider
                touchIDView
            }
        }
    }

    private var passwordSection: some View {
        SecureField(text: $password) {
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
            reason: Text("View saved passwords"),
        ) { result in
            handleTouchIDResult(result)
        }
        .controlSize(.large)
    }

    // MARK: - Touch ID Handler

    private func handleTouchIDResult(_ result: Result<Void, any Error>) {
        switch result {
        case .success:
            isAuthenticated = true

        case let .failure(authError):
            if let laError = authError as? LAError {
                switch laError.code {
                case .userCancel:
                    isPasswordFieldFocused = true
                case .biometryLockout:
                    withAnimation {
                        error = "Touch ID is locked. Please use your password."
                    }
                    isPasswordFieldFocused = true
                case .biometryNotAvailable, .biometryNotEnrolled:
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

    private func authenticateWithPassword() {
        guard !password.isEmpty else { return }

        isAuthenticating = true
        error = nil

        // Authenticate using macOS login password via LAContext
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        Task {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "View saved passwords",
                )
                await MainActor.run {
                    isAuthenticating = false
                    if success {
                        isAuthenticated = true
                        password = ""
                    }
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    withAnimation {
                        self.error = "Authentication failed. Please try again."
                    }
                    password = ""
                }
            }
        }
    }
}

#if DEBUG
    #Preview(traits: .modifier(RefraxPreviewModifier())) {
        PasswordsView()
    }
#endif
