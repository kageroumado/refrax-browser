import SwiftUI
import WebKit

/// Sheet displaying security analysis results before extension installation.
///
/// Shows risk level, warnings, and capabilities to help users make informed
/// decisions about whether to install an extension.
struct SecurityWarningSheet: View {
    /// The security report to display.
    let report: SecurityReport

    /// The extension being analyzed.
    let extensionName: String

    /// Icon data for the extension, if available.
    let iconData: Data?

    /// Called when user cancels installation.
    let onCancel: () -> Void

    /// Called when user proceeds with installation.
    let onInstall: () -> Void

    @State private var hasAcknowledged = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Risk summary
                    riskSummary

                    // Warnings
                    if !report.permissionWarnings.isEmpty || !report.codeWarnings.isEmpty {
                        warningsSection
                    }

                    // Capabilities
                    if !report.capabilities.isEmpty {
                        capabilitiesSection
                    }

                    // Recommendation
                    recommendationSection
                }
                .padding(24)
            }

            Divider()

            // Actions
            actions
                .padding(20)
        }
        .frame(width: 520, height: min(600, 700))
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            // Extension icon
            extensionIcon
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Security Review")
                    .font(.headline)

                Text(extensionName)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Spacer()

            // Risk badge
            riskBadge
        }
    }

    @ViewBuilder
    private var extensionIcon: some View {
        if let iconData, let nsImage = NSImage(data: iconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.appAccentColor.opacity(0.15))
                .overlay {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var riskBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: riskIcon)
                .font(.system(size: 14, weight: .semibold))

            Text(report.riskLevel.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(riskColor.opacity(0.15))
        .foregroundStyle(riskColor)
        .clipShape(Capsule())
    }

    private var riskIcon: String {
        switch report.riskLevel {
        case .low: "checkmark.shield"
        case .medium: "exclamationmark.shield"
        case .high: "exclamationmark.triangle"
        case .critical: "xmark.shield"
        }
    }

    private var riskColor: Color {
        switch report.riskLevel {
        case .low: .green
        case .medium: .yellow
        case .high: .orange
        case .critical: .red
        }
    }

    // MARK: - Risk Summary

    private var riskSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            let warningCount = report.permissionWarnings.count + report.codeWarnings.count

            if warningCount == 0 {
                Label("No security issues detected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(
                    "\(warningCount) security \(warningCount == 1 ? "issue" : "issues") found",
                    systemImage: "exclamationmark.triangle.fill",
                )
                .foregroundStyle(riskColor)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Warnings Section

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Warnings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(report.permissionWarnings.enumerated()), id: \.offset) { _, warning in
                    WarningRow(
                        icon: "key.fill",
                        severity: warning.severity,
                        message: warning.message,
                        permissions: warning.permissions,
                    )
                }

                ForEach(Array(report.codeWarnings.enumerated()), id: \.offset) { _, warning in
                    WarningRow(
                        icon: "doc.text.fill",
                        severity: warning.severity,
                        message: warning.message,
                        detail: warning.filePath,
                    )
                }
            }
        }
    }

    // MARK: - Capabilities Section

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What this extension can do")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(Set(report.capabilities)).sorted(), id: \.self) { capability in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)

                        Text(capability)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Recommendation Section

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendation")
                .font(.headline)

            Text(report.recommendation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            // Acknowledgment checkbox for high-risk extensions
            if report.requiresExplicitAcknowledgment {
                Toggle(isOn: $hasAcknowledged) {
                    Text("I understand the risks and want to proceed")
                        .font(.subheadline)
                }
                .toggleStyle(.checkbox)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button(installButtonTitle) {
                    onInstall()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(report.riskLevel >= .high ? .orange : .appAccentColor)
                .disabled(report.requiresExplicitAcknowledgment && !hasAcknowledged)
            }
        }
    }

    private var installButtonTitle: String {
        switch report.riskLevel {
        case .low, .medium:
            "Install"
        case .high, .critical:
            "Install Anyway"
        }
    }
}

// MARK: - Warning Row

private struct WarningRow: View {
    let icon: String
    let severity: RiskLevel
    let message: String
    var permissions: [String]?
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(severityColor)
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if let permissions, !permissions.isEmpty {
                    Text(permissions.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Severity indicator
            Text(severity.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(severityColor.opacity(0.15))
                .foregroundStyle(severityColor)
                .clipShape(Capsule())
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var severityColor: Color {
        switch severity {
        case .low: .green
        case .medium: .yellow
        case .high: .orange
        case .critical: .red
        }
    }
}

// MARK: - Preview

#Preview("Low Risk") {
    SecurityWarningSheet(
        report: SecurityReport(
            riskLevel: .low,
            permissionWarnings: [],
            codeWarnings: [],
            recommendation: "This extension appears safe to use.",
            analyzedAt: Date(),
        ),
        extensionName: "Simple Extension",
        iconData: nil,
        onCancel: {},
        onInstall: {},
    )
}

#Preview("High Risk") {
    SecurityWarningSheet(
        report: SecurityReport(
            riskLevel: .high,
            permissionWarnings: [
                PermissionWarning(
                    permissions: ["<all_urls>"],
                    severity: .high,
                    message: "Requests access to all websites",
                    capabilities: ["Read and modify content on any website"],
                ),
                PermissionWarning(
                    permissions: ["cookies"],
                    severity: .medium,
                    message: "Can access cookies",
                    capabilities: ["Read cookies for websites"],
                ),
            ],
            codeWarnings: [
                CodeWarning(
                    pattern: .dataExfiltration,
                    severity: .medium,
                    message: "Sends data to external server",
                    filePath: "/background.js",
                    lineNumber: nil,
                ),
            ],
            recommendation: "This extension requests powerful permissions. Only install if you trust the developer.",
            analyzedAt: Date(),
        ),
        extensionName: "Risky Extension",
        iconData: nil,
        onCancel: {},
        onInstall: {},
    )
}
