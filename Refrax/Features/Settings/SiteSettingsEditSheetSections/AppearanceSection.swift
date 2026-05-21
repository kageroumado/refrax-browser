import SwiftUI

/// Appearance settings section for site settings edit sheet.
///
/// Contains dark mode override, page filter, background removal,
/// content protection bypass, window coloring, and PiP preferences.
struct SiteSettingsAppearanceSection: View {
    @Binding var darkModeOverride: DarkModeOverride
    @Binding var pageFilterOverride: PageFilterOverride
    @Binding var backgroundRemovalOverride: BackgroundRemovalOverride
    @Binding var contentProtectionBypass: Bool?
    @Binding var websiteColoringPolicy: WebsiteColoringPolicy
    @Binding var pipPreference: PiPPreference

    var body: some View {
        Section("Appearance") {
            Picker("Dark Mode", selection: $darkModeOverride) {
                ForEach(DarkModeOverride.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Page Filter", selection: $pageFilterOverride) {
                ForEach(PageFilterOverride.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }

            Picker("Background Removal", selection: $backgroundRemovalOverride) {
                ForEach(BackgroundRemovalOverride.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Content Protection Bypass", selection: contentProtectionBypassBinding) {
                Text("Use Default").tag(ContentProtectionBypassOption.useDefault)
                Text("Always Enable").tag(ContentProtectionBypassOption.forceOn)
                Text("Never Enable").tag(ContentProtectionBypassOption.forceOff)
            }
            .help("Override text selection and copying restrictions")

            Picker("Window Coloring", selection: $websiteColoringPolicy) {
                ForEach(WebsiteColoringPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .help("Whether this site can tint the window background")

            Picker("Auto Picture-in-Picture", selection: $pipPreference) {
                ForEach(PiPPreference.allCases, id: \.self) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }
        }
    }

    /// Binding adapter for tri-state content protection bypass.
    private var contentProtectionBypassBinding: Binding<ContentProtectionBypassOption> {
        Binding(
            get: {
                switch contentProtectionBypass {
                case nil: .useDefault
                case true: .forceOn
                case false: .forceOff
                }
            },
            set: { newValue in
                contentProtectionBypass = switch newValue {
                case .useDefault: nil
                case .forceOn: true
                case .forceOff: false
                }
            },
        )
    }
}

/// Tri-state option for per-site content protection bypass setting.
enum ContentProtectionBypassOption {
    case useDefault
    case forceOn
    case forceOff
}
