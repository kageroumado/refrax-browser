import SwiftUI

/// Custom About window matching Apple's standard About panel styling.
struct AboutView: View {
    private let version: String = {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(marketing) (\(build))"
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            appIcon
            VStack(alignment: .leading, spacing: 0) {
                appNameAndVersion
                Spacer()
                    .frame(height: 16)
                copyright
                Spacer()
                    .frame(height: 8)
                contactLinks
                Spacer()
                    .frame(height: 16)
                buttons
            }
        }
        .padding(EdgeInsets(top: 28, leading: 28, bottom: 24, trailing: 28))
        .frame(width: 520)
        .fixedSize()
    }

    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 128, height: 128)
    }

    private var appNameAndVersion: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Refrax")
                .font(.system(size: 32, weight: .regular))
            Text(version)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var copyright: some View {
        Text("Copyright \u{00A9} 2026 kageroumado. Licensed under GPL-3.0.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contactLinks: some View {
        HStack(spacing: 4) {
            Link("refrax.website", destination: URL.staticRequired("https://refrax.website"))
            Text("·").foregroundStyle(.secondary)
            Link("kagerou.glass", destination: URL.staticRequired("https://kagerou.glass"))
            Text("·").foregroundStyle(.secondary)
            Link("@kageroumado", destination: URL.staticRequired("https://x.com/kageroumado"))
        }
        .font(.system(size: 11))
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button("Acknowledgements") {
                NSApp.typedDelegate.acknowledgementsWindowController.showWindow()
            }
            .controlSize(.large)

            Button("License Agreement") {
                NSApp.typedDelegate.licenseAgreementWindowController.showWindow()
            }
            .controlSize(.large)
        }
    }
}
