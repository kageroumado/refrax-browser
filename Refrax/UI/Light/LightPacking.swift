import CoreGraphics
import Foundation

/// Packs ``LightPath`` values into the flat float array the `lightPaths` shader reads.
///
/// The layout, mirrored by the constants at the top of `LightPaths.metal`:
///
/// ```
/// header     [0] path count   [1] segment count
/// paths      one record of `pathStride` floats per path, in order:
///              0 first segment index   1 segment count   2 length   3 lit length
///              4 red   5 green   6 blue   7 intensity
///              8 core width   9 glow width   10 dispersion   11 spot scale
///             12–14 low band rgb   15 pad   16–18 high band rgb   19 pad
/// segments   one record of `segmentStride` floats per segment, all paths in order:
///              0 ax   1 ay   2 bx   3 by   4 start along the path   5 length   6 dir x   7 dir y
/// ```
///
/// At most ``maximumSegments`` segments are packed. A path whose segments would cross
/// the cap is left out, with every path after it.
nonisolated enum LightPacking {
    /// The most segments one shader pass draws, summed over every path.
    static let maximumSegments = 32
    static let headerLength = 2
    static let pathStride = 20
    static let segmentStride = 8

    static func pack(_ paths: [LightPath]) -> [Float] {
        var kept: [LightPath] = []
        var segmentCount = 0
        for path in paths {
            let segments = path.points.count - 1
            guard segmentCount + segments <= maximumSegments else { break }
            kept.append(path)
            segmentCount += segments
        }

        var data = [Float](repeating: 0, count: headerLength + kept.count * pathStride + segmentCount * segmentStride)
        data[0] = Float(kept.count)
        data[1] = Float(segmentCount)

        var segmentIndex = 0
        let segmentBase = headerLength + kept.count * pathStride
        for (pathIndex, path) in kept.enumerated() {
            let record = headerLength + pathIndex * pathStride
            let lengths = path.segmentLengths
            let length = lengths.reduce(0, +)
            let bands = path.bandColors
            data[record] = Float(segmentIndex)
            data[record + 1] = Float(lengths.count)
            data[record + 2] = Float(length)
            data[record + 3] = Float(min(max(path.progress, 0), 1) * length)
            data[record + 4] = Float(path.color.red)
            data[record + 5] = Float(path.color.green)
            data[record + 6] = Float(path.color.blue)
            data[record + 7] = Float(min(max(path.intensity, 0), 1))
            data[record + 8] = Float(path.coreWidth)
            data[record + 9] = Float(path.glowWidth)
            data[record + 10] = Float(min(max(path.dispersion, 0), 1))
            data[record + 11] = Float(path.spotScale)
            data[record + 12] = Float(bands.low.red)
            data[record + 13] = Float(bands.low.green)
            data[record + 14] = Float(bands.low.blue)
            data[record + 16] = Float(bands.high.red)
            data[record + 17] = Float(bands.high.green)
            data[record + 18] = Float(bands.high.blue)

            var start: CGFloat = 0
            for (index, segmentLength) in lengths.enumerated() {
                let a = path.points[index]
                let b = path.points[index + 1]
                let offset = segmentBase + segmentIndex * segmentStride
                data[offset] = Float(a.x)
                data[offset + 1] = Float(a.y)
                data[offset + 2] = Float(b.x)
                data[offset + 3] = Float(b.y)
                data[offset + 4] = Float(start)
                data[offset + 5] = Float(segmentLength)
                if segmentLength > 0 {
                    data[offset + 6] = Float((b.x - a.x) / segmentLength)
                    data[offset + 7] = Float((b.y - a.y) / segmentLength)
                }
                start += segmentLength
                segmentIndex += 1
            }
        }
        return data
    }
}
