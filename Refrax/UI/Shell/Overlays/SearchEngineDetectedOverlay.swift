import SwiftUI

// MARK: - Search Engine Detected Overlay

/// Overlay pill shown when a site's search engine is detected.
///
/// Observes `windowState.pendingSearchEngineDetection` and shows a Liquid Glass
/// pill at the top of the window. The user can add the engine or dismiss.
/// Auto-dismisses after 8 seconds if no action is taken.
struct SearchEngineDetectedOverlay: View {
    @Environment(WindowState.self) private var windowState
    @Environment(CustomSearchEngineManager.self) private var customSearchEngineManager

    var body: some View {
        Group {
            if let detection = windowState.pendingSearchEngineDetection {
                // Skip if already a custom engine for this domain
                if !customSearchEngineManager.engineExists(forDomain: detection.domain) {
                    SearchEngineDetectedPill(detection: detection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 16)
                        .offset(x: windowState.sidebarThickness / 2)
                        .ignoresSafeArea()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.3), value: windowState.pendingSearchEngineDetection != nil)
    }
}

// MARK: - Search Engine Detected Pill

/// Liquid Glass pill displaying the detected engine name with Add/Dismiss actions.
private struct SearchEngineDetectedPill: View {
    let detection: DetectedSearchEngine

    @Environment(WindowState.self) private var windowState
    @Environment(CustomSearchEngineManager.self) private var customSearchEngineManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(.secondary)

            Text("\(detection.name) supports search")
                .font(.body)
                .lineLimit(1)

            Button("Add") {
                addEngine()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .glassEffect()
        .task(id: detection.domain) {
            do {
                try await Task.sleep(for: .seconds(8))
                dismiss()
            } catch {
                // Cancelled — view removed before timer fired
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            windowState.isHoveringOverlayNotification = hovering
            if hovering {
                NSCursor.arrow.set()
            }
        }
        .onDisappear {
            windowState.isHoveringOverlayNotification = false
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(detection.name) supports search. Add as search engine?")
    }

    private func addEngine() {
        let alias = customSearchEngineManager.generateAlias(from: detection.domain)

        customSearchEngineManager.add(
            name: detection.name,
            alias: alias,
            searchURLTemplate: detection.searchURLTemplate,
            suggestionURLTemplate: detection.suggestionURLTemplate,
            parserKind: detection.parserKind,
            sourceDomain: detection.domain,
            isAutoDetected: true,
        )

        windowState.pendingSearchEngineDetection = nil
        windowState.showToast("Added \(detection.name) as search engine")
    }

    private func dismiss() {
        windowState.dismissedSearchEngineDomains.insert(detection.domain)
        windowState.pendingSearchEngineDetection = nil
    }
}
