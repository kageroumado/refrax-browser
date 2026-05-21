import SwiftUI

/// Apple's continuous corner rounded rectangle shape (squircle).
///
/// This shape matches the corner style used by macOS app icons and iOS home screen icons.
/// It uses SwiftUI's `.continuous` corner style which provides smooth curvature transitions
/// instead of abrupt circular arcs.
///
/// ## Corner Radius Ratio
///
/// The default ratio of 9/32 (28.125%) approximates macOS Tahoe app icons (28%)
/// while yielding exact integer corner radii for power-of-2 sizes (16, 32, 64, 128...).
///
/// ## Usage
///
/// ```swift
/// // As a shape
/// SquircleShape()
///     .fill(.blue)
///     .frame(width: 64, height: 64)
///
/// // As a clip shape
/// Image(nsImage: favicon)
///     .clipShape(SquircleShape())
///
/// // With custom ratio
/// SquircleShape(cornerRadiusRatio: 0.25)  // 25% for tighter corners
/// ```
struct SquircleShape: Shape {
    /// The ratio of corner radius to the smaller dimension.
    ///
    /// Default is 9/32 (28.125%), approximating macOS Tahoe icons with bitmap-friendly math.
    var cornerRadiusRatio: CGFloat

    /// Creates a squircle shape with the standard Apple icon corner ratio.
    init() {
        self.cornerRadiusRatio = 9 / 32
    }

    /// Creates a squircle shape with a custom corner radius ratio.
    ///
    /// - Parameter cornerRadiusRatio: The ratio of corner radius to size (0.0 to 0.5).
    init(cornerRadiusRatio: CGFloat) {
        self.cornerRadiusRatio = cornerRadiusRatio
    }

    func path(in rect: CGRect) -> Path {
        let minDimension = min(rect.width, rect.height)
        let cornerRadius = minDimension * cornerRadiusRatio
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: rect)
    }
}

// MARK: - View Modifier

extension View {
    /// Clips the view to Apple's squircle shape.
    ///
    /// Uses 9/32 (28.125%) corner radius ratio, approximating macOS Tahoe app icons.
    ///
    /// - Returns: The view clipped to a squircle shape.
    func clipToSquircle() -> some View {
        clipShape(SquircleShape())
    }

    /// Clips the view to a squircle shape with a custom corner ratio.
    ///
    /// - Parameter cornerRadiusRatio: The ratio of corner radius to size (0.0 to 0.5).
    /// - Returns: The view clipped to a squircle shape.
    func clipToSquircle(cornerRadiusRatio: CGFloat) -> some View {
        clipShape(SquircleShape(cornerRadiusRatio: cornerRadiusRatio))
    }
}

// MARK: - Insettable Shape

extension SquircleShape: InsettableShape {
    func inset(by amount: CGFloat) -> some InsettableShape {
        InsetSquircleShape(cornerRadiusRatio: cornerRadiusRatio, inset: amount)
    }
}

/// An inset version of SquircleShape for stroke borders.
struct InsetSquircleShape: InsettableShape {
    var cornerRadiusRatio: CGFloat
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: inset, dy: inset)
        let minDimension = min(insetRect.width, insetRect.height)
        let cornerRadius = minDimension * cornerRadiusRatio
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: insetRect)
    }

    func inset(by amount: CGFloat) -> InsetSquircleShape {
        InsetSquircleShape(cornerRadiusRatio: cornerRadiusRatio, inset: inset + amount)
    }
}

// MARK: - Preview

#Preview("Squircle Shapes") {
    HStack(spacing: 20) {
        // Standard squircle
        SquircleShape()
            .fill(.blue)
            .frame(width: 64, height: 64)

        // With image
        Image(systemName: "star.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(12)
            .background(.orange)
            .frame(width: 64, height: 64)
            .clipToSquircle()

        // Comparison: Circle
        Circle()
            .fill(.green)
            .frame(width: 64, height: 64)

        // Comparison: Standard rounded rect (circular arcs, not continuous)
        RoundedRectangle(cornerRadius: 64 * 9 / 32, style: .circular)
            .fill(.purple)
            .frame(width: 64, height: 64)
    }
    .padding()
}
