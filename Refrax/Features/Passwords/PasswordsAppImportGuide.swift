import AppKit
import SwiftUI

/// Opens Apple's Passwords app so the user can hand its logins to Refrax over
/// Credential Exchange.
enum PasswordsApp {
    static let bundleIdentifier = "com.apple.Passwords"

    /// Launches (or foregrounds) the Passwords app. Returns whether it was found.
    @discardableResult
    static func open() -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            Logger.error("Passwords app not found on this Mac", category: Logger.autoFill)
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }
}

/// Step-by-step guide for pulling logins out of Apple's Passwords app straight
/// into Refrax, without an intermediate CSV. Mirrors the export flow Passwords
/// exposes under File ▸ Export All Passwords.
struct PasswordsAppImportGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 440, height: 440)
    }

    private var header: some View {
        HStack {
            Text("Import from the Passwords App")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                instructionGroup(
                    step: 1,
                    title: "Open the Passwords app",
                    description: "Use the button below, or open **Passwords** from Applications.",
                )

                instructionGroup(
                    step: 2,
                    title: "Start an export",
                    description: "In Passwords, choose **File** ▸ **Export All Passwords…**",
                    note: "Authenticate with Touch ID or your Mac password when prompted.",
                )

                instructionGroup(
                    step: 3,
                    title: "Choose Refrax",
                    description: "Pick **Refrax** in the “Select a Destination” list, then click **Continue**.",
                    note: "Not listed? Turn Refrax on in System Settings ▸ General ▸ AutoFill & Passwords.",
                )

                instructionGroup(
                    step: 4,
                    title: "Done",
                    description: "Your logins transfer straight into Refrax — no file to clean up afterward.",
                )

                securityNote
            }
            .padding()
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Passwords") {
                PasswordsApp.open()
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func instructionGroup(
        step: Int,
        title: String,
        description: LocalizedStringKey,
        note: String? = nil,
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appAccentColor)
                    .frame(width: 28, height: 28)

                Text("\(step)")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Why this is better than a CSV")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Passwords are handed to Refrax through Apple's encrypted Credential Exchange — they are never written to a plain-text file on disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.08)),
        )
    }
}
