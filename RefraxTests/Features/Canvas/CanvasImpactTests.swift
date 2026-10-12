import AVFAudio
import CoreGraphics
import Foundation
import Testing
@testable import Refrax

@MainActor
struct CanvasImpactTests {
    private let desk = CGRect(x: 0, y: 0, width: 2_000, height: 1_200)
    private let first = UUID(uuidString: "20203000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "E0D0B000-0000-0000-0000-000000000002")!

    @Test
    func `passive layout has no impact feedback`() {
        var world = CanvasPhysics(desk: desk)
        world.place(first, frame: CGRect(x: 500, y: 400, width: 320, height: 200))
        world.place(second, frame: CGRect(x: 650, y: 400, width: 320, height: 200))
        let events = world.step(1.0 / 20)
        #expect(impacts(in: events).isEmpty)
    }

    @Test
    func `collision reports one contact across solver passes`() throws {
        var world = CanvasPhysics(desk: desk)
        world.place(first, frame: CGRect(x: 500, y: 400, width: 320, height: 200))
        world.place(second, frame: CGRect(x: 838, y: 400, width: 320, height: 200))
        world.release(first, velocity: CGPoint(x: 600, y: 0), dropped: true)
        let contacts = impacts(in: world.step(1.0 / 20))
        #expect(contacts.count == 1)
        let contact = try #require(contacts.first)
        #expect(contact.speed > 500)
        #expect(contact.point.x > 800)
        #expect(contact.normal == CGPoint(x: 1, y: 0))
    }

    @Test
    func `small slab yields to heavier preview`() throws {
        var world = CanvasPhysics(desk: desk)
        world.place(first, frame: CGRect(x: 500, y: 450, width: 208, height: 12))
        world.place(second, frame: CGRect(x: 726, y: 400, width: 320, height: 200))
        world.release(first, velocity: CGPoint(x: 600, y: 0), dropped: true)
        _ = world.step(1.0 / 120)
        let small = try #require(world.bodies[first])
        let large = try #require(world.bodies[second])
        #expect(small.velocity.x < large.velocity.x)
        #expect(large.velocity.x > 0)
        #expect(large.velocity.x < 600)
    }

    @Test
    func `continuous contact does not rattle`() {
        var world = CanvasPhysics(desk: desk)
        world.place(first, frame: CGRect(x: 500, y: 400, width: 320, height: 200))
        world.place(second, frame: CGRect(x: 838, y: 400, width: 320, height: 200))
        world.drag(first, to: CGRect(x: 500, y: 400, width: 320, height: 200), elapsed: 0)
        var contacts: [CanvasPhysics.Impact] = []
        for step in 1 ... 12 {
            world.drag(first, to: CGRect(x: 500 + step * 5, y: 400, width: 320, height: 200), elapsed: 1.0 / 120)
            contacts += impacts(in: world.step(1.0 / 120))
        }
        #expect(contacts.count == 1)
    }

    @Test
    func `material is stable and varies across tabs`() {
        let a = CanvasPhysics.Material(id: first)
        let b = CanvasPhysics.Material(id: second)
        #expect(a == CanvasPhysics.Material(id: first))
        #expect(a != b)
        #expect(a.restitution > 0 && a.restitution < 1)
        #expect(b.restitution > 0 && b.restitution < 1)
    }

    @Test(arguments: 0 ..< 8)
    func `click is decodable and quiet at its boundaries`(variant: Int) throws {
        let player = try AVAudioPlayer(data: CanvasClickSynthesis.wave(variant: variant))
        #expect(abs(player.duration - CanvasClickSynthesis.duration) < 0.001)
        let samples = CanvasClickSynthesis.samples(variant: variant)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) < 1 })
        #expect(try #require(samples.first) == 0)
        #expect(try abs(#require(samples.last)) < 0.0001)
    }

    private func impacts(in events: [CanvasPhysics.Event]) -> [CanvasPhysics.Impact] {
        events.compactMap {
            if case let .impact(impact) = $0 {
                impact
            } else {
                nil
            }
        }
    }
}
