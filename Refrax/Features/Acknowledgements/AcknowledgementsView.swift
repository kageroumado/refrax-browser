import SwiftUI

/// Displays third-party software licenses bundled with Refrax.
struct AcknowledgementsView: View {
    private let licenseText: String = Self.loadLicenses()

    var body: some View {
        ScrollView {
            Text(licenseText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    /// License files bundled in Resources (Xcode flattens the Licenses/ folder).
    private static let licenseFileNames = [
        "readability",
        "aria2",
        "gpl-2.0",
        "ublock-origin",
    ]

    private static func loadLicenses() -> String {
        let separator = "\n\n" + String(repeating: "=", count: 72) + "\n\n"

        let sections = licenseFileNames.compactMap { name -> String? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }
            return text
        }

        if sections.isEmpty {
            return "No license information available."
        }

        return sections.joined(separator: separator)
    }
}
