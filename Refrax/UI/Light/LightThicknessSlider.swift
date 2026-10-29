import SwiftUI

/// The light thickness setting: a slider from thin to bold with the current scale beside it,
/// shared by Settings › Appearance and the Control Island's Customize sheet.
struct LightThicknessSlider: View {
    @Binding var thickness: Double

    private enum Layout {
        static let sliderWidth: CGFloat = 200
        static let valueWidth: CGFloat = 36
        static let step = 0.1
    }

    var body: some View {
        HStack {
            Text("Light thickness")
            Spacer()
            Slider(value: $thickness, in: BrowserSettings.Defaults.lightThicknessRange, step: Layout.step) {
                Text("Light thickness")
            } minimumValueLabel: {
                Text("Thin").font(.caption)
            } maximumValueLabel: {
                Text("Bold").font(.caption.weight(.bold))
            }
            .labelsHidden()
            .frame(width: Layout.sliderWidth)
            Text(thickness.formatted(.number.precision(.fractionLength(1))) + "×")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: Layout.valueWidth, alignment: .trailing)
        }
        .help("How thick beams of light are drawn: the rays from controls, the trail to the page card, and the empty page")
    }
}
