import SwiftUI

/// Shows whether a local agent CLI is installed and where.
///
/// The file-system probe runs synchronously for the first frame; a login-shell
/// lookup then fills in installs outside the usual directories.
struct CLIAgentStatusView: View {
    let runtime: CLIAgentRuntime

    @State private var location: URL?
    @State private var isSearching = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Uses your \(runtime.displayName) login")
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                statusIcon
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: runtime) {
            location = CLIAgentLocator.installedURL(for: runtime)
            isSearching = location == nil
            if location == nil {
                location = await CLIAgentLocator.locate(runtime)
            }
            isSearching = false
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if location != nil {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if isSearching {
            ProgressView()
                .controlSize(.mini)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusText: String {
        if let location {
            "Found at \(location.path(percentEncoded: false))"
        } else if isSearching {
            "Looking for \(runtime.executableName)…"
        } else {
            "Not found. \(runtime.installHint)"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        CLIAgentStatusView(runtime: .claudeCode)
        CLIAgentStatusView(runtime: .codex)
    }
    .padding()
    .frame(width: 360)
}
