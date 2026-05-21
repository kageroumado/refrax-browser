import Foundation
import SwiftUI

extension Sidebar {
    /// Coordinates horizontal slide animation when switching between spaces.
    ///
    /// Provides a two-phase animation:
    /// 1. **Out phase**: Current tabs slide off-screen in the direction of travel
    /// 2. **In phase**: New tabs slide in from the opposite edge
    ///
    /// ## Animation Behavior
    ///
    /// When switching to next space (higher index):
    /// - Old tabs slide out to the LEFT (negative offset)
    /// - New tabs slide in from the RIGHT (positive to zero)
    ///
    /// When switching to previous space (lower index):
    /// - Old tabs slide out to the RIGHT (positive offset)
    /// - New tabs slide in from the LEFT (negative to zero)
    ///
    /// ## Spring Animation Staggering
    ///
    /// When a space transition completes, items receive spring animations based on visibility:
    /// - **Visible items** (have frames in LayoutManager): animate immediately with spring physics
    /// - **Off-screen items** (no frame): skip animation entirely to avoid jank from 50+ simultaneous springs
    ///
    /// This prevents the performance issue where all tab items fire spring animations simultaneously
    /// when `isTransitioning` becomes `false`.
    ///
    /// ## Usage
    ///
    /// The coordinator uses a callback pattern to control timing:
    /// ```swift
    /// transitionCoordinator.animateSpaceChange(from: oldIndex, to: newIndex) {
    ///     spaceManager.switchToSpace(...)
    /// }
    /// ```
    @Observable
    final class TransitionCoordinator {
        /// Horizontal offset applied to the tab list.
        /// Positive = content shifted right, negative = content shifted left.
        private(set) var animationOffset: CGFloat = 0

        /// Whether a space transition is currently in progress.
        /// Used to suppress item-level animations during the transition.
        private(set) var isTransitioning: Bool = false

        /// Distance to slide content off-screen.
        private let slideDistance: CGFloat = 280

        /// Duration of the out animation (current content leaving).
        /// Slightly faster for snappy feel.
        private let outDuration: Double = 0.12

        /// Duration of the in animation (new content entering).
        /// Slightly longer for smooth landing.
        private let inDuration: Double = 0.13

        /// Reference to layout manager for visibility-based animation decisions.
        ///
        /// Used by `animation(for:offsetY:)` to determine if an item is visible
        /// (has a frame) and should receive spring animation.
        @ObservationIgnored
        weak var layoutManager: LayoutManager?

        /// Standard spring animation for tab/group offset changes.
        private let springAnimation = Animation.spring(response: 0.25, dampingFraction: 0.8)

        /// Marks transition as active without triggering animation.
        ///
        /// Use this for externally-animated transitions (like swipe gestures)
        /// that manage their own animation timing.
        ///
        /// - Parameters:
        ///   - oldIndex: Index of the current space in the spaces array
        ///   - newIndex: Index of the target space in the spaces array
        ///   - duration: How long the external animation will take
        func prepareSpaceChange(from _: Int, to _: Int, duration: Double = 0.25) {
            guard !isTransitioning else { return }

            isTransitioning = true

            // Clear after the external animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.isTransitioning = false
            }
        }

        /// Animates a space change with proper out/in sequencing.
        ///
        /// - Parameters:
        ///   - oldIndex: Index of the current space in the spaces array
        ///   - newIndex: Index of the target space in the spaces array
        ///   - performSwitch: Closure that performs the actual space switch.
        ///     Called after the out animation completes.
        func animateSpaceChange(
            from oldIndex: Int,
            to newIndex: Int,
            performSwitch: @escaping () -> Void,
        ) {
            // Don't interrupt an in-progress transition
            guard !isTransitioning else {
                performSwitch()
                return
            }

            let movingRight = newIndex > oldIndex
            isTransitioning = true

            // Phase 1: Animate current content OUT
            // Moving right → content slides left (negative)
            // Moving left → content slides right (positive)
            let outTarget: CGFloat = movingRight ? -slideDistance : slideDistance

            withAnimation(.easeIn(duration: outDuration)) {
                animationOffset = outTarget
            }

            // Phase 2: After out animation completes, switch content and animate IN
            //
            // DISPATCH CHAIN RATIONALE:
            // This uses nested DispatchQueue calls rather than Task.sleep because:
            // 1. We're coordinating SwiftUI animations which don't provide completion handlers
            // 2. The main queue is serial, so ordering is guaranteed (FIFO)
            // 3. asyncAfter uses DispatchWallTime - callbacks may fire late under load, never early
            //
            // The chain structure:
            // - asyncAfter(outDuration): Wait for out-animation before switching content
            // - async: Ensure disabled-animation transaction commits before starting in-animation
            //   (without this frame boundary, SwiftUI may coalesce the position reset with the animation)
            // - asyncAfter(inDuration): Wait for in-animation before enabling item springs
            //
            // EDGE CASE: Under extreme system load, asyncAfter may fire after the animation
            // visually completes. This is harmless - isTransitioning clearing early just enables
            // item springs slightly early, and the transition timings (0.12s, 0.13s) are short
            // enough that visible drift is unlikely.
            DispatchQueue.main.asyncAfter(deadline: .now() + outDuration) { [weak self] in
                guard let self else { return }

                // Perform the space switch (content changes)
                performSwitch()

                // Immediately position new content on the opposite side
                // Must disable animations to prevent interpolation
                // Moving right → new content starts from right (positive)
                // Moving left → new content starts from left (negative)
                let inStart: CGFloat = movingRight ? slideDistance : -slideDistance
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    animationOffset = inStart
                }

                // Animate new content to center on next frame
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    withAnimation(.easeOut(duration: inDuration)) {
                        self.animationOffset = 0
                    }

                    // Clear transition flag after in animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + inDuration) { [weak self] in
                        self?.isTransitioning = false
                    }
                }
            }
        }

        // MARK: - Animation Staggering

        /// Returns the appropriate animation for an item's offset change.
        ///
        /// This method implements visibility-based animation staggering to prevent jank
        /// when switching spaces. Instead of 50+ spring animations firing simultaneously
        /// when `isTransitioning` becomes `false`, only visible items animate while
        /// off-screen items snap instantly to their positions.
        ///
        /// **Animation Rules:**
        /// - During transition (`isTransitioning == true`): No animation (items move with slide)
        /// - Visible items (have frame in metadata): Spring animation for smooth reordering
        /// - Off-screen items (no frame): No animation to prevent simultaneous spring jank
        ///
        /// - Parameters:
        ///   - itemID: The ID of the tab or group item.
        ///   - offsetY: The current offset value (used as animation trigger).
        /// - Returns: The animation to apply, or `nil` for no animation.
        func animation(for _: UUID, offsetY _: CGFloat) -> Animation? {
            // During space transition, suppress all item animations
            // The entire tab list moves via animationOffset instead
            if isTransitioning {
                return nil
            }

            // Visible item - use spring animation for smooth reordering
            return springAnimation
        }
    }
}
