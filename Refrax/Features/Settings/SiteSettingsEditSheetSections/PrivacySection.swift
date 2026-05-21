import SwiftUI

/// Privacy settings section for site settings edit sheet.
///
/// Contains auto-consent toggle and GPC signal override.
struct SiteSettingsPrivacySection: View {
    @Binding var disableAutoConsent: Bool
    @Binding var gpcHeaderOverride: GPCHeaderOverride

    var body: some View {
        Section("Privacy") {
            Toggle("Disable Auto-Consent", isOn: $disableAutoConsent)
                .help("Skip automatic cookie banner dismissal for this site")

            Picker("GPC Signal", selection: $gpcHeaderOverride) {
                ForEach(GPCHeaderOverride.allCases, id: \.self) { override in
                    Text(override.displayName).tag(override)
                }
            }
        }
    }
}
