import SwiftUI

/// The three telemetry tiers as radio rows, each with its one-sentence summary.
///
/// Shared by onboarding and Settings → Privacy, so both explain the choice
/// in the same words.
struct TelemetryTierPicker: View {
    @Binding var tier: TelemetryTier

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(TelemetryTier.allCases, id: \.self) { option in
                row(for: option)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Telemetry")
    }

    private func row(for option: TelemetryTier) -> some View {
        Button {
            tier = option
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: option == tier ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(option == tier ? Color.appAccentColor : .secondary)
                    .imageScale(.medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                    Text(option.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(option == tier ? [.isButton, .isSelected] : .isButton)
    }
}

/// A "What's sent" disclosure listing the exact fields the selected tier shares.
struct TelemetryDisclosureView: View {
    let tier: TelemetryTier

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("What\u{2019}s sent", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                switch tier {
                case .off:
                    Text("Nothing. Refrax keeps no usage record while telemetry is off.")
                        .foregroundStyle(.secondary)
                case .counting:
                    fieldList("Once a day, on days you use Refrax", TelemetryDisclosure.checkInFields)
                case .crashReports:
                    fieldList("Once a day, on days you use Refrax", TelemetryDisclosure.checkInFields)
                    fieldList("After a crash, on the next launch", TelemetryDisclosure.crashReportFields)
                }
            }
            .font(.caption)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fieldList(_ heading: String, _ fields: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(heading)
                .fontWeight(.semibold)
            ForEach(fields, id: \.self) { field in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\u{2022}")
                    Text(field)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
