import SwiftUI

/// Content settings section for site settings edit sheet.
///
/// Contains page zoom, JavaScript toggle, content blockers,
/// reader mode preference, and pop-up/auto-play policies.
struct SiteSettingsContentSection: View {
    @Binding var pageZoom: Double
    @Binding var allowJavaScript: Bool
    @Binding var enableContentBlockers: Bool
    @Binding var useReaderWhenAvailable: Bool
    @Binding var popUpPolicy: PopUpPolicy
    @Binding var autoPlayPolicy: AutoPlayPolicy

    var body: some View {
        Section("Content") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Page Zoom")
                    Spacer()
                    Text("\(Int(pageZoom))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $pageZoom, in: 50 ... 200, step: 5)
            }
            .padding(.vertical, 2)

            Toggle("Enable JavaScript", isOn: $allowJavaScript)

            Toggle("Enable Content Blockers", isOn: $enableContentBlockers)

            Toggle("Use Reader when available", isOn: $useReaderWhenAvailable)

            Picker("Pop-ups", selection: $popUpPolicy) {
                ForEach(PopUpPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }

            Picker("Auto-Play", selection: $autoPlayPolicy) {
                ForEach(AutoPlayPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
        }
    }
}
