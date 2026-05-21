import SwiftUI

// MARK: - Memory Graph View

/// A compact rolling line chart showing web, GPU, and app memory over time.
///
/// Draws three smooth lines using quadratic bezier curves with subtle gradient
/// fills. Auto-scales the Y-axis to the maximum observed value. Designed to
/// fit in the Lightboard header at ~60pt height.
///
/// The web line includes unmapped process memory (prewarmed/orphan processes)
/// so the graph total matches the header total.
struct MemoryGraphView: View {
    let history: [MemoryDataPoint]

    /// Version counter from ProcessMemoryMonitor to trigger redraws.
    let historyVersion: Int

    private enum Constants {
        static let height: CGFloat = 60
        static let gridLineCount = 3
        static let fillOpacity: Double = 0.1
        static let lineWidth: CGFloat = 1.5
        static let dashPattern: [CGFloat] = [4, 3]
    }

    /// The actual maximum value across all series, including unmapped memory in the web line.
    private var maxValue: Int {
        let maxPoint = history.reduce(0) { current, point in
            max(current, point.webMB + point.unmappedMB, point.gpuMB, point.appMB)
        }
        return max(maxPoint, 1)
    }

    /// Padded maximum used for y-axis scaling so the peak doesn't touch the top edge.
    private var paddedMaxValue: Int {
        max(Int(Double(maxValue) * 1.15), maxValue + 1)
    }

    /// Midpoint label value for the Y-axis.
    private var midValue: Int {
        maxValue / 2
    }

    var body: some View {
        if history.count >= 2 {
            ZStack(alignment: .trailing) {
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                    drawLine(context: context, size: size, values: history.map(\.appMB), color: .orange)
                    drawLine(context: context, size: size, values: history.map(\.gpuMB), color: .green)
                    drawLine(context: context, size: size, values: history.map { $0.webMB + $0.unmappedMB }, color: .blue)
                    drawMaxLine(context: context, size: size)
                }

                VStack {
                    Text("\(maxValue)")
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Spacer()

                    Text("\(midValue)")
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Spacer()

                    Text("0")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 4)
                .padding(.vertical, 2)
            }
            .frame(height: Constants.height)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Drawing

    /// Draws subtle horizontal grid lines.
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let color = Color.primary.opacity(0.06)
        for i in 1...Constants.gridLineCount {
            let fraction = CGFloat(i) / CGFloat(Constants.gridLineCount + 1)
            let y = size.height * (1.0 - fraction)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
    }

    /// Draws a smooth line with gradient fill for a series of values.
    private func drawLine(
        context: GraphicsContext,
        size: CGSize,
        values: [Int],
        color: Color
    ) {
        guard values.count >= 2 else { return }

        let points = values.enumerated().map { index, value -> CGPoint in
            let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let y = size.height * (1.0 - CGFloat(value) / CGFloat(paddedMaxValue))
            return CGPoint(x: x, y: y)
        }

        let linePath = smoothPath(through: points)
        context.stroke(linePath, with: .color(color), lineWidth: Constants.lineWidth)

        var fillPath = linePath
        fillPath.addLine(to: CGPoint(x: points.last!.x, y: size.height))
        fillPath.addLine(to: CGPoint(x: points.first!.x, y: size.height))
        fillPath.closeSubpath()

        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [color.opacity(Constants.fillOpacity), color.opacity(0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
    }

    /// Draws a dashed horizontal line at the current maximum value.
    private func drawMaxLine(context: GraphicsContext, size: CGSize) {
        let y = size.height * (1.0 - CGFloat(maxValue) / CGFloat(paddedMaxValue))
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(
            path,
            with: .color(.primary.opacity(0.15)),
            style: StrokeStyle(lineWidth: 0.5, dash: Constants.dashPattern)
        )
    }

    /// Creates a smooth path through points using quadratic bezier curves.
    private func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for i in 1..<points.count {
            let current = points[i]
            let previous = points[i - 1]
            let midPoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )

            path.addQuadCurve(to: midPoint, control: previous)

            if i == points.count - 1 {
                path.addQuadCurve(to: current, control: midPoint)
            }
        }

        return path
    }
}
