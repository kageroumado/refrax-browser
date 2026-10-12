import AVFAudio
import Foundation

/// A small voice bank of soft, dry contacts, mixed at the user's system volume.
@MainActor
final class CanvasImpactSound {
    var isEnabled = false {
        didSet {
            if isEnabled {
                prepare()
            } else {
                players.forEach { $0.stop() }
            }
        }
    }

    private var players: [AVAudioPlayer] = []
    private var lastVoice: Int?
    private var lastPlayedAt: TimeInterval = -.infinity

    private enum Constants {
        static let voices = 8
        static let minimumInterval: TimeInterval = 0.065
        static let maximumSpeed: CGFloat = 1_000
        static let minimumVolume: Float = 0.12
        static let volumeRange: Float = 0.3
        static let stereoWidth: Float = 0.55
    }

    func play(speed: CGFloat, pan: CGFloat, at time: TimeInterval) {
        guard isEnabled, time - lastPlayedAt >= Constants.minimumInterval else { return }
        let available = players.indices.filter { !players[$0].isPlaying && $0 != lastVoice }
        guard let index = available.randomElement() else { return }
        let player = players[index]
        let strength = Float(min(1, max(0, speed / Constants.maximumSpeed)))
        let volume = UserDefaults.standard.object(forKey: "canvasImpactVolume") as? Double ?? 0.6
        player.volume = (Constants.minimumVolume + sqrt(strength) * Constants.volumeRange) * Float(min(1, max(0, volume)))
        player.pan = Float(min(1, max(-1, pan))) * Constants.stereoWidth
        player.currentTime = 0
        if player.play() {
            lastPlayedAt = time
            lastVoice = index
        }
    }

    /// Auditions one contact in Settings, including while desk sounds are disabled.
    func preview() {
        isEnabled = true
        play(speed: 450, pan: 0, at: ProcessInfo.processInfo.systemUptime)
    }

    private func prepare() {
        guard players.isEmpty else { return }
        players = (0 ..< Constants.voices).compactMap { variant in
            guard let player = try? AVAudioPlayer(data: CanvasClickSynthesis.wave(variant: variant)) else { return nil }
            player.prepareToPlay()
            return player
        }
    }
}

/// Two damped impulses with a rounded attack and a short, filtered contact texture.
nonisolated enum CanvasClickSynthesis {
    static let sampleRate = 44_100
    static let duration = 0.055

    static func wave(variant: Int) -> Data {
        let samples = samples(variant: variant)
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data("RIFF".utf8)
        append(byteCount + 36, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(byteCount, to: &data)
        for sample in samples {
            append(Int16((sample * Double(Int16.max)).rounded()), to: &data)
        }
        return data
    }

    static func samples(variant: Int) -> [Double] {
        let character = Double(variant % 8) / 7
        let frequency = 760 + character * 210
        let secondContact = 0.004 + character * 0.002
        var noiseState = UInt64(truncatingIfNeeded: variant) &+ 1
        var filteredNoise = 0.0
        return (0 ..< Int(Double(sampleRate) * duration)).map { frame in
            let t = Double(frame) / Double(sampleRate)
            noiseState = noiseState &* 6_364_136_223_846_793_005 &+ 1
            let noise = Double(noiseState >> 32) / Double(UInt32.max) * 2 - 1
            filteredNoise += 0.22 * (noise - filteredNoise)
            let first = impulse(at: t, frequency: frequency)
            let second = 0.42 * impulse(at: t - secondContact, frequency: frequency * 0.83)
            let texture = filteredNoise * exp(-t / 0.005) * min(1, t / 0.0008) * 0.14
            let tail = min(1, max(0, (duration - t) / 0.006))
            return (first + second + texture) * tail * 0.62
        }
    }

    private static func impulse(at time: Double, frequency: Double) -> Double {
        guard time >= 0 else { return 0 }
        let envelope = (1 - exp(-time / 0.00045)) * exp(-time / 0.005)
        return envelope * (sin(2 * .pi * frequency * time) * 0.75 + sin(2 * .pi * frequency * 1.73 * time) * 0.25)
    }

    private static func append(_ value: some FixedWidthInteger, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
