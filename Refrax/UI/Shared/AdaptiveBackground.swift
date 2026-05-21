import SwiftUI

// MARK: - Environment Values

extension EnvironmentValues {
    /// When true, adaptive backgrounds include the expensive BackdropBlurView layer.
    ///
    /// Defaults to false. Only enable for views where blur enhances UX (overlays, address bar).
    /// The blur layer uses CABackdropLayer which has significant rendering cost.
    @Entry var adaptiveBackgroundBlurEnabled: Bool = false
}

extension View {
    /// Enables the blur effect for adaptive backgrounds in this view hierarchy.
    ///
    /// Use for overlays, popovers, and inputs where blur enhances the UX.
    /// Disabled by default to avoid CABackdropLayer rendering cost on high-frequency views.
    func adaptiveBackgroundBlur(_ enabled: Bool = true) -> some View {
        environment(\.adaptiveBackgroundBlurEnabled, enabled)
    }
}

// MARK: - Adaptive Background Style

/// Visual style for adaptive background effects.
///
/// Provides backdrop blur with adaptive colors for light and dark modes.
enum AdaptiveBackgroundStyle {
    /// No visible background.
    case clear

    /// Subtle background with light tint. Default for interactive elements.
    case subtle

    /// Muted background with darker tint. For "action" items that aren't activatable.
    /// Used for shortcuts, folders, and app shortcuts in favorites grid to distinguish
    /// them from live favorites which can be selected/activated.
    case muted

    /// Prominent background with glow and stroke effects. For active/selected state.
    case emphasized

    /// Secondary selection indicator. Less prominent than emphasized.
    case secondary

    /// Combines emphasized background with secondary indicator border.
    case emphasizedSecondary
}

// MARK: - Constants

enum AdaptiveBackgroundConstants {
    static let glowStrokeWidth: CGFloat = 1.5
    static let outerStrokeWidth: CGFloat = 0.5
    static let shadowRadius: CGFloat = 2
    static let shadowOffsetY: CGFloat = 1
    static let shadowOpacity: CGFloat = 0.08
    static let secondaryOpacity: CGFloat = 0.7
    static let blurRadius: CGFloat = 10

    /// Multiplier applied to window background mix amount for element tint overlays.
    ///
    /// Element backgrounds use the window's color strength scaled by this value.
    /// This ensures elements remain visually harmonious without being over-saturated,
    /// since they're already rendered on top of the colored window background.
    static let elementTintStrengthMultiplier: CGFloat = 0.5
}

// MARK: - Adaptive Background Modifier

/// A view modifier that applies adaptive background styling with backdrop blur.
///
/// Uses CABackdropLayer for true backdrop blur effects, with adaptive colors
/// for light and dark modes.
///
/// ## Styles
///
/// - **clear**: No background
/// - **subtle**: Light tint with blur
/// - **emphasized**: Prominent background with glow and stroke
/// - **secondary**: Subdued selection indicator
/// - **emphasizedSecondary**: Combined emphasized + secondary border
///
/// ## Usage
///
/// ```swift
/// Text("Hello")
///     .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 8))
///
/// Button("Action") { }
///     .adaptiveBackground(.emphasized, in: Capsule())
/// ```
struct AdaptiveBackgroundModifier<S: InsettableShape>: ViewModifier {
    @Environment(WindowState.self) private var windowState
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.adaptiveBackgroundBlurEnabled) private var blurEnabled

    let style: AdaptiveBackgroundStyle
    let shape: S

    // Cached gradient to avoid recreation on every body render
    @State private var cachedGlowGradient: LinearGradient?
    @State private var lastGlowStyle: AdaptiveBackgroundStyle?

    func body(content: Content) -> some View {
        content
            .background {
                backgroundContent
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
    }

    @ViewBuilder
    private var backgroundContent: some View {
        switch style {
        case .clear:
            Color.clear

        case .subtle:
            ZStack {
                if blurEnabled {
                    BackdropBlurView(blurRadius: AdaptiveBackgroundConstants.blurRadius)
                }
                Color(.sidebarItemHover)
                tintOverlay
            }

        case .muted:
            ZStack {
                if blurEnabled {
                    BackdropBlurView(blurRadius: AdaptiveBackgroundConstants.blurRadius)
                }
                Color(.sidebarItemMuted)
                tintOverlay
            }

        case .emphasized:
            ZStack {
                emphasizedBackground
            }

        case .secondary:
            ZStack {
                if blurEnabled {
                    BackdropBlurView(blurRadius: AdaptiveBackgroundConstants.blurRadius)
                }
                secondaryBackground
            }

        case .emphasizedSecondary:
            ZStack {
                emphasizedSecondaryBackground
            }
        }
    }

    private var tintOverlay: some View {
        let tintOpacity = settings.windowBackgroundMixAmount * AdaptiveBackgroundConstants.elementTintStrengthMultiplier
        return Color(windowState.backgroundColor.color)
            .opacity(tintOpacity)
            .blendMode(.color)
    }

    private var emphasizedBackground: some View {
        ZStack {
            Color(.sidebarItemSelected)

            shape
                .strokeBorder(
                    glowGradient,
                    lineWidth: AdaptiveBackgroundConstants.glowStrokeWidth,
                )

            shape
                .strokeBorder(
                    Color(.sidebarItemSelectedStroke),
                    lineWidth: AdaptiveBackgroundConstants.outerStrokeWidth,
                )
        }
    }

    private var secondaryBackground: some View {
        ZStack {
            Color(.sidebarItemSelected)
                .opacity(AdaptiveBackgroundConstants.secondaryOpacity)

            shape
                .strokeBorder(
                    Color.appAccentColor.opacity(0.5),
                    lineWidth: AdaptiveBackgroundConstants.outerStrokeWidth,
                )
        }
    }

    private var emphasizedSecondaryBackground: some View {
        ZStack {
            Color(.sidebarItemSelected)
                .shadow(
                    color: Color.black.opacity(AdaptiveBackgroundConstants.shadowOpacity),
                    radius: AdaptiveBackgroundConstants.shadowRadius,
                    x: 0,
                    y: AdaptiveBackgroundConstants.shadowOffsetY,
                )

            shape
                .strokeBorder(
                    glowGradient,
                    lineWidth: AdaptiveBackgroundConstants.glowStrokeWidth,
                )

            shape
                .strokeBorder(
                    Color.appAccentColor.opacity(0.6),
                    lineWidth: AdaptiveBackgroundConstants.outerStrokeWidth + 0.5,
                )
        }
    }

    private var glowGradient: LinearGradient {
        if let cached = cachedGlowGradient, lastGlowStyle == style {
            return cached
        }

        let gradient = LinearGradient(
            colors: [
                Color(.sidebarItemSelectedGlow),
                Color(.sidebarItemSelectedGlow).opacity(0.6),
                Color(.sidebarItemSelectedGlow).opacity(0.3),
                Color.clear,
            ],
            startPoint: .top,
            endPoint: .bottom,
        )

        // Update cache on next run loop to avoid modifying state during view update
        DispatchQueue.main.async {
            cachedGlowGradient = gradient
            lastGlowStyle = style
        }

        return gradient
    }
}

// MARK: - View Extension

extension View {
    /// Applies an adaptive background with backdrop blur and the specified style.
    ///
    /// - Parameters:
    ///   - style: The visual style to apply.
    ///   - shape: The shape for clipping and stroke borders.
    /// - Returns: A view with the adaptive background applied.
    func adaptiveBackground(
        _ style: AdaptiveBackgroundStyle,
        in shape: some InsettableShape,
    ) -> some View {
        modifier(AdaptiveBackgroundModifier(style: style, shape: shape))
    }
}
