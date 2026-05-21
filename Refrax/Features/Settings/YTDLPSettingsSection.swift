import SwiftUI

/// Settings section for yt-dlp video downloads.
///
/// Shows install status, Homebrew install button, and per-feature toggles.
/// yt-dlp is not bundled — installed on-demand via Homebrew.
struct YTDLPSettingsSection: View {
    @Bindable var settings: BrowserSettings
    let highlightedItemId: String?

    @State private var installState: InstallState = .idle
    @State private var detectedVersion: String?
    @State private var isChecking = true

    private enum InstallState {
        case idle
        case installing
        case success(String)
        case failed(String)
    }

    var body: some View {
        Section {
            Toggle("Enable video downloads", isOn: $settings.ytdlpEnabled)
                .highlightable(id: "general.ytdlp", highlightedItemId: highlightedItemId)

            if settings.ytdlpEnabled {
                // Status row
                HStack {
                    Text("yt-dlp")
                    Spacer()
                    statusView
                }
                .highlightable(id: "general.ytdlpStatus", highlightedItemId: highlightedItemId)

                if detectedVersion != nil {
                    Toggle("Use browser cookies", isOn: $settings.ytdlpUseCookies)
                        .highlightable(
                            id: "general.ytdlpUseCookies",
                            highlightedItemId: highlightedItemId,
                        )

                    Toggle(
                        "Delete file after Photos import",
                        isOn: $settings.ytdlpDeleteAfterPhotosImport,
                    )
                    .highlightable(
                        id: "general.ytdlpDeleteAfterImport",
                        highlightedItemId: highlightedItemId,
                    )
                }
            }
        } header: {
            Text("Video Downloads")
        } footer: {
            if settings.ytdlpEnabled {
                footerText
            } else {
                Text(
                    "Download videos from YouTube, Vimeo, TikTok, and thousands of other sites using yt-dlp."
                )
            }
        }
        .task {
            await checkInstallation()
        }
        .onChange(of: settings.ytdlpEnabled) { _, enabled in
            if enabled {
                Task { await checkInstallation() }
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusView: some View {
        if isChecking {
            ProgressView()
                .controlSize(.small)
        } else if let version = detectedVersion {
            Text(version)
                .foregroundStyle(.secondary)
        } else {
            switch installState {
            case .idle, .failed:
                Button("Install with Homebrew") {
                    Task { await install() }
                }
                .buttonStyle(.link)
            case .installing:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing…")
                        .foregroundStyle(.secondary)
                }
            case let .success(version):
                Text(version)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var footerText: some View {
        switch installState {
        case let .failed(message):
            Text("Installation failed: \(message)")
                .foregroundStyle(.red)
        default:
            if detectedVersion != nil {
                Text(
                    "Downloads videos from supported sites via the right-click menu. Browser cookies allow downloading age-restricted and private content."
                )
            } else {
                Text(
                    "Requires yt-dlp. Install via Homebrew, or manually from [github.com/yt-dlp](https://github.com/yt-dlp/yt-dlp)."
                )
            }
        }
    }

    // MARK: - Actions

    private func checkInstallation() async {
        isChecking = true
        defer { isChecking = false }

        if let path = YTDLPService.findBinary() {
            do {
                let version = try await YTDLPService.shared.version()
                detectedVersion = version
            } catch {
                // Binary found but version query failed — still usable
                detectedVersion = path.contains("homebrew") ? "installed (Homebrew)" : "installed"
            }
        } else {
            detectedVersion = nil
        }
    }

    private func install() async {
        installState = .installing

        do {
            let version = try await YTDLPService.installWithHomebrew()
            installState = .success(version)
            await YTDLPService.shared.invalidateBinaryCache()
            detectedVersion = version
        } catch {
            installState = .failed(error.localizedDescription)
        }
    }
}
