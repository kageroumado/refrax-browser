import SwiftUI

/// Time limits settings section for site settings edit sheet.
///
/// Contains daily time limit toggle and duration picker,
/// along with time spent tracking display.
struct SiteSettingsTimeLimitsSection: View {
    let domain: String
    let domainTimeTracker: DomainTimeTracker

    @Binding var timeLimitEnabled: Bool
    @Binding var timeLimitMinutes: Int

    @State private var timeSpent: TimeInterval = 0

    var body: some View {
        Section("Time Limits") {
            Toggle("Daily Time Limit", isOn: $timeLimitEnabled)
                .help("Limit how long you can browse this site per day")

            if timeLimitEnabled {
                Picker("Limit", selection: $timeLimitMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                    Text("1 hour").tag(60)
                    Text("1.5 hours").tag(90)
                    Text("2 hours").tag(120)
                    Text("3 hours").tag(180)
                    Text("4 hours").tag(240)
                }

                HStack {
                    Text("Time spent today")
                    Spacer()
                    Text(timeSpent.formattedDuration)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            timeSpent = await domainTimeTracker.timeSpent(on: domain)
        }
    }
}
