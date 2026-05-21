import SwiftUI

/// Floating instruction overlay shown during the interactive guided tour.
///
/// Positioned at the bottom-center of the window, this overlay shows
/// the current step's instruction with a step indicator and skip button.
/// It detects user actions via `onChange` on observable state properties
/// and automatically advances the tour when each step is completed.
struct GuidedTourOverlay: View {
    @Environment(GuidedTourManager.self) private var tourManager
    @Environment(WindowState.self) private var windowState
    @Environment(BrowserState.self) private var browserState

    /// Tab count at the time each step is entered, used to detect new tab creation.
    @State private var tabCountAtStepStart = 0

    var body: some View {
        if let step = tourManager.currentStep {
            VStack {
                Spacer()

                tourBubble(step: step)
                    .padding(.bottom, Layout.bottomPadding)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(true)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.4), value: tourManager.currentStep)
            .onChange(of: windowState.showsCommandLens) { _, isOpen in
                handleCommandLensChange(isOpen: isOpen)
            }
            .onChange(of: browserState.tabListVersion) { _, _ in
                handleTabListChange()
            }
            .onChange(of: windowState.isInLayoutMode) { _, isInLayout in
                if isInLayout, tourManager.currentStep == .enterLayoutMode {
                    tourManager.advance()
                }
            }
            .onChange(of: windowState.isInspectorCollapsed) { _, isCollapsed in
                if !isCollapsed, tourManager.currentStep == .openReferencePane {
                    tourManager.advance()
                }
            }
            .onChange(of: tourManager.currentStep) { _, newStep in
                if let newStep, newStep != .completed {
                    recordTabCount()
                }
                if newStep == .completed {
                    scheduleAutoDismiss()
                }
            }
            .onAppear {
                recordTabCount()
            }
        }
    }

    // MARK: - Tour Bubble

    private func tourBubble(step: GuidedTourManager.Step) -> some View {
        VStack(spacing: Layout.bubbleSpacing) {
            // Step indicator
            if step != .completed {
                Text("Step \(step.stepNumber) of \(GuidedTourManager.Step.totalSteps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            // Icon + instruction
            HStack(spacing: Layout.iconTextSpacing) {
                Image(systemName: step.icon)
                    .font(.system(size: Layout.iconSize, weight: .medium))
                    .foregroundStyle(step == .completed ? .green : .primary)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(step == .completed ? 1.2 : 1.0)

                Text(step.instruction)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(.spring(duration: 0.3), value: step == .completed)

            // Skip button (not shown on completion)
            if step != .completed {
                Button("Skip Tour") {
                    tourManager.cancel()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Layout.bubblePaddingH)
        .padding(.vertical, Layout.bubblePaddingV)
        .frame(maxWidth: Layout.maxWidth)
        .glassEffect(.regular, in: .rect(cornerRadius: Layout.cornerRadius))
    }

    // MARK: - Action Detection

    private func handleCommandLensChange(isOpen: Bool) {
        guard isOpen else { return }
        if tourManager.currentStep == .openCommandLens {
            tourManager.advance()
        }
    }

    private func handleTabListChange() {
        guard let step = tourManager.currentStep,
              step == .createFirstTab || step == .createSecondTab else { return }

        let currentCount = currentTabCount()
        if currentCount > tabCountAtStepStart {
            tourManager.advance()
        }
    }

    private func currentTabCount() -> Int {
        guard let space = windowState.activeSpace else { return 0 }
        return browserState.tabs(in: space).count
    }

    private func recordTabCount() {
        tabCountAtStepStart = currentTabCount()
    }

    private func scheduleAutoDismiss() {
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            tourManager.cancel()
        }
    }

    // MARK: - Layout

    private enum Layout {
        static let bottomPadding: CGFloat = 40
        static let bubbleSpacing: CGFloat = 8
        static let iconTextSpacing: CGFloat = 12
        static let iconSize: CGFloat = 24
        static let bubblePaddingH: CGFloat = 24
        static let bubblePaddingV: CGFloat = 16
        static let maxWidth: CGFloat = 480
        static let cornerRadius: CGFloat = 20
    }
}
