import SwiftData
import SwiftUI

extension View {
    // MARK: - Conditional Modifiers

    /// Conditionally applies a transformation to a view
    /// - Parameters:
    ///   - condition: Whether to apply the transformation
    ///   - transform: The transformation to apply
    /// - Returns: The transformed view if condition is true, otherwise the original view
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Conditionally applies a transformation to a view, with an else clause
    /// - Parameters:
    ///   - condition: Whether to apply the if transformation
    ///   - ifTransform: The transformation to apply if condition is true
    ///   - elseTransform: The transformation to apply if condition is false
    /// - Returns: The transformed view
    @ViewBuilder
    func `if`(
        _ condition: Bool,
        if ifTransform: (Self) -> some View,
        else elseTransform: (Self) -> some View,
    ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }
    
    /// View modifier to flash a view briefly
    func flash(_ shouldFlash: Bool) -> some View {
        opacity(shouldFlash ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.2).repeatCount(3, autoreverses: true), value: shouldFlash)
    }
}
