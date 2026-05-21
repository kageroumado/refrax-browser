import SwiftUI

/// Overlay view displayed when a domain's daily time limit has been exceeded.
///
/// When users spend more time on a domain than their configured limit,
/// this overlay appears with a blur effect over the page content.
/// Users can snooze the limit (up to 3 times per day, 5 minutes each)
/// or close the tab.
///
/// ## Behavior
///
/// - Shows when domain time exceeds configured limit
/// - Snooze adds 5 minutes to the effective limit
/// - Maximum 3 snoozes per 24-hour rolling window
/// - Snooze count resets automatically after 24 hours
struct TimeLimitOverlayView: View {
    let domain: String
    let timeSpent: TimeInterval
    let timeLimit: TimeInterval
    let snoozesRemaining: Int
    let onSnooze: () -> Void
    let onCloseTab: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Timer icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "timer")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
            }

            // Title
            Text("Time Limit Reached")
                .font(.title2)
                .fontWeight(.semibold)

            // Time info
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Time spent:")
                        .foregroundStyle(.secondary)
                    Text(timeSpent.formattedDuration)
                        .fontWeight(.medium)
                }

                HStack(spacing: 4) {
                    Text("Daily limit:")
                        .foregroundStyle(.secondary)
                    Text(timeLimit.formattedDuration)
                        .fontWeight(.medium)
                }
            }
            .font(.subheadline)

            // Explanation
            Text("You've reached your daily time limit for \(domain). Take a break or extend your time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            // Action buttons
            HStack(spacing: 16) {
                // Snooze button
                Button {
                    onSnooze()
                } label: {
                    Label(snoozeButtonLabel, systemImage: "clock.badge.questionmark")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(snoozesRemaining <= 0)

                // Close tab button
                Button {
                    onCloseTab()
                } label: {
                    Label("Close Tab", systemImage: "xmark.circle")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            // Snooze info
            if snoozesRemaining > 0 {
                Text("\(snoozesRemaining) snooze\(snoozesRemaining == 1 ? "" : "s") remaining today")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No snoozes remaining today")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Private

    private var snoozeButtonLabel: String {
        if snoozesRemaining > 0 {
            "+5 minutes"
        } else {
            "No snoozes"
        }
    }
}

// MARK: - Preview

#Preview("Time Limit Overlay", traits: .modifier(RefraxPreviewModifier())) {
    ZStack {
        Text("Web page content behind the overlay")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)

        TimeLimitOverlayView(
            domain: "twitter.com",
            timeSpent: 2_100,
            timeLimit: 1_800,
            snoozesRemaining: 2,
            onSnooze: { print("Snoozed!") },
            onCloseTab: { print("Close tab!") },
        )
    }
    .frame(width: 600, height: 400)
}

#Preview("No Snoozes Left", traits: .modifier(RefraxPreviewModifier())) {
    ZStack {
        Text("Web page content behind the overlay")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)

        TimeLimitOverlayView(
            domain: "reddit.com",
            timeSpent: 7_500,
            timeLimit: 3_600,
            snoozesRemaining: 0,
            onSnooze: {},
            onCloseTab: { print("Close tab!") },
        )
    }
    .frame(width: 600, height: 400)
}
