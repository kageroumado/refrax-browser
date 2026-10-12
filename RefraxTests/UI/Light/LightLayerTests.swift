import CoreGraphics
import Foundation
import Metal
import SwiftUI
import Testing
@testable import Refrax

/// Runs the `lightPaths` shader from the app's Metal library over a texture and reads it back.
@Suite
struct LightLayerTests {
    private let violet = Color.Components(red: 0.5, green: 0.2, blue: 0.9)
    private let size = 128

    @Test func `the shader lights the diagonal and leaves the far corners clear`() throws {
        let path = LightPath(points: [CGPoint(x: 16, y: 16), CGPoint(x: 112, y: 112)], color: violet)
        let pixels = try LightProbe.render([path], width: size, height: size)

        for along in [CGPoint(x: 16, y: 16), CGPoint(x: 40, y: 40), CGPoint(x: 64, y: 64), CGPoint(x: 100, y: 100), CGPoint(x: 112, y: 112)] {
            let pixel = pixels[along]
            #expect(pixel.alpha > 0.6, "\(along) sits on the core")
            #expect(pixel.red <= pixel.alpha + 0.01 && pixel.green <= pixel.alpha + 0.01 && pixel.blue <= pixel.alpha + 0.01, "premultiplied")
        }
        let halo = pixels[CGPoint(x: 64 + 5, y: 64 - 5)]
        #expect(halo.alpha > 0.05 && halo.alpha < pixels[CGPoint(x: 64, y: 64)].alpha, "the halo is dimmer than the core")
        #expect(halo.blue > halo.red, "the halo carries the path's color")
        for far in [CGPoint(x: 112, y: 16), CGPoint(x: 16, y: 112), CGPoint(x: 4, y: 64), CGPoint(x: 124, y: 60)] {
            #expect(pixels[far].alpha == 0, "\(far) is far from the beam")
        }
    }

    @Test func `progress lights the path from its start`() throws {
        var path = LightPath(points: [CGPoint(x: 8, y: 64), CGPoint(x: 120, y: 64)], color: violet)
        path.progress = 0.5
        let pixels = try LightProbe.render([path], width: size, height: size)
        #expect(pixels[CGPoint(x: 30, y: 64)].alpha > 0.6)
        #expect(pixels[CGPoint(x: 64, y: 64)].alpha > 0.6, "the tip spot sits at the lit end")
        #expect(pixels[CGPoint(x: 100, y: 64)].alpha < 0.01, "beyond the lit length only the tip halo's tail remains")
        path.progress = 0
        #expect(try LightProbe.render([path], width: size, height: size)[CGPoint(x: 8, y: 64)].alpha == 0)
    }

    @Test func `dispersion fans the last segment into bands of neighboring hues`() throws {
        var path = LightPath(points: [CGPoint(x: 8, y: 64), CGPoint(x: 24, y: 64), CGPoint(x: 124, y: 64)], color: violet)
        path.glowWidth = 4
        path.dispersion = 0
        let straight = try LightProbe.render([path], width: size, height: size)
        path.dispersion = 1
        let fanned = try LightProbe.render([path], width: size, height: size)

        // 100 pt past the bend a 6° band sits 10.5 pt off the center line.
        let above = CGPoint(x: 124, y: 64 - 10.5)
        let below = CGPoint(x: 124, y: 64 + 10.5)
        #expect(straight[above].alpha == 0 && straight[below].alpha == 0)
        #expect(fanned[above].alpha > 0.3 && fanned[below].alpha > 0.3)
        #expect(fanned[CGPoint(x: 124, y: 64)].alpha > 0.3, "the center band stays")
        #expect(fanned[above].red != fanned[below].red || fanned[above].blue != fanned[below].blue, "the outer bands differ in hue")
        #expect(fanned[CGPoint(x: 16, y: 64 - 10.5)].alpha == 0, "the first segment keeps one beam")
    }

    @Test func `intensity scales the light and an empty set draws nothing`() throws {
        var path = LightPath(points: [CGPoint(x: 16, y: 64), CGPoint(x: 112, y: 64)], color: violet)
        let full = try LightProbe.render([path], width: size, height: size)[CGPoint(x: 64, y: 64)].alpha
        path.intensity = 0.25
        let dim = try LightProbe.render([path], width: size, height: size)[CGPoint(x: 64, y: 64)].alpha
        #expect(dim > 0 && dim < full)
        let none = try LightProbe.render([], width: 8, height: 8)
        #expect(none.pixels.allSatisfy { $0 == 0 })
    }
}

/// Dispatches `lightPathsProbe` over a texture of the given size.
nonisolated enum LightProbe {
    struct Image {
        let width: Int
        let height: Int
        let pixels: [Float]

        subscript(point: CGPoint) -> (red: Float, green: Float, blue: Float, alpha: Float) {
            let x = min(max(Int(point.x), 0), width - 1)
            let y = min(max(Int(point.y), 0), height - 1)
            let offset = (y * width + x) * 4
            return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
        }
    }

    static func render(_ paths: [LightPath], width: Int, height: Int) throws -> Image {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: AppDelegate.self))
        let function = try #require(library.makeFunction(name: "lightPathsProbe"))
        let pipeline = try device.makeComputePipelineState(function: function)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))

        let data = LightPacking.pack(paths)
        let buffer = try #require(device.makeBuffer(bytes: data, length: max(data.count, 1) * MemoryLayout<Float>.stride, options: .storageModeShared))
        var count = Int32(data.count)

        let queue = try #require(device.makeCommandQueue())
        let command = try #require(queue.makeCommandBuffer())
        let encoder = try #require(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.setBytes(&count, length: MemoryLayout<Int32>.stride, index: 1)
        encoder.setTexture(texture, index: 0)
        let threadWidth = pipeline.threadExecutionWidth
        let threadHeight = pipeline.maxTotalThreadsPerThreadgroup / threadWidth
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        #expect(command.status == .completed)

        var halves = [Float16](repeating: 0, count: width * height * 4)
        halves.withUnsafeMutableBytes { bytes in
            texture.getBytes(bytes.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float16>.stride, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return Image(width: width, height: height, pixels: halves.map(Float.init))
    }
}
