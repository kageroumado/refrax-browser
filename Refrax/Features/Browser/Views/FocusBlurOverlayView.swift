import SwiftUI

/// Overlay view for Focus Mode blurred domains.
///
/// When Focus Mode is active with blurred domains configured, this overlay appears
/// over web content for matching domains. The content is visually blurred until
/// the user explicitly clicks to reveal it.
///
/// ## Behavior
///
/// - Shows when navigating to a domain in the blurred list
/// - User clicks "Reveal Content" to see the page
/// - Once revealed, remains visible until Focus Mode changes
/// - Less restrictive than blocked domains (content is still accessible)
struct FocusBlurOverlayView: View {
    let domain: String
    let onReveal: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Focus icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
            }

            // Title
            Text("Content Hidden")
                .font(.title2)
                .fontWeight(.semibold)

            // Explanation
            Text("This page is blurred during Focus Mode to help you stay productive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            // Reveal button
            Button {
                onReveal()
            } label: {
                Label("Reveal Content", systemImage: "eye")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Domain indicator
            Text(domain)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview("Focus Blur Overlay", traits: .modifier(RefraxPreviewModifier())) {
    ZStack {
        Text("Web page content behind the overlay")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)

        FocusBlurOverlayView(domain: "reddit.com") {
            print("Revealed!")
        }
    }
    .frame(width: 600, height: 400)
}
