import SwiftUI

/// Toast notification displayed when a URL is detected in the clipboard.
///
/// Provides quick actions to open the URL in the current tab, a new tab,
/// or a background tab. Auto-dismisses after 5 seconds unless the user
/// interacts with it.
struct ClipboardURLToast: View {
    @Environment(ClipboardMonitor.self) private var clipboardMonitor
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState

    let url: URL

    /// Callback when the toast should be dismissed.
    var onDismiss: () -> Void

    @State private var isHovering = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "link.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.blue)

            // URL info
            VStack(alignment: .leading, spacing: 2) {
                Text("URL Copied")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(displayURL)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .help(url.absoluteString)
            }

            Spacer(minLength: 8)

            // Actions
            HStack(spacing: 6) {
                ToastButton(title: "Open", icon: "arrow.right.circle") {
                    openInCurrentTab()
                }

                ToastButton(title: "New Tab", icon: "plus.square") {
                    openInNewTab()
                }

                ToastButton(title: "Background", icon: "square.stack") {
                    openInBackgroundTab()
                }
            }

            // Dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .adaptiveBackground(.emphasized, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                // Cancel auto-dismiss when hovering
                dismissTask?.cancel()
            } else {
                // Restart auto-dismiss timer
                scheduleAutoDismiss()
            }
        }
        .onAppear {
            scheduleAutoDismiss()
        }
        .onDisappear {
            dismissTask?.cancel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("URL detected in clipboard: \(url.host ?? "unknown domain")")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Display

    private var displayURL: String {
        // Show host with path, truncated if too long
        var display = url.host ?? url.absoluteString

        if let path = url.path.nilIfEmpty, path != "/" {
            let maxPathLength = 30
            if path.count > maxPathLength {
                display += path.prefix(maxPathLength) + "..."
            } else {
                display += path
            }
        }

        return display
    }

    // MARK: - Actions

    private func openInCurrentTab() {
        if let activePage = windowState.activePage,
           let webPage = tabManager.pagePool.page(for: activePage) {
            webPage.load(url)
        }
        dismiss()
    }

    private func openInNewTab() {
        tabManager.createTab(url: url, in: windowState.activeSpace, makeActive: true, loadImmediately: true)
        dismiss()
    }

    private func openInBackgroundTab() {
        tabManager.createTab(url: url, in: windowState.activeSpace, makeActive: false, loadImmediately: true)
        dismiss()
    }

    private func dismiss() {
        dismissTask?.cancel()
        clipboardMonitor.clearDetectedURL()
        onDismiss()
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

// MARK: - Toast Button

private struct ToastButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovering ? Color.appAccentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
