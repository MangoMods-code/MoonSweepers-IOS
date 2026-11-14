import AVFoundation

/// All sound is synthesised at launch, so the app ships with no audio files.
final class Sfx {
    static let shared = Sfx()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var loops: [String: AVAudioPlayerNode] = [:]
    private var shots: [AVAudioPlayerNode] = []
    private var nextShot = 0
    private var running = false
    var enabled = true {
        didSet { engine.mainMixerNode.outputVolume = enabled ? 1 : 0 }
    }

    private func make(_ name: String, seconds: Double, _ f: (Double, Int) -> Double) {
        let n = Int(seconds * 44100)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(n)
        for i in 0..<n {
            ch[0][i] = Float(max(-1, min(1, f(Double(i) / 44100, i))))
        }
        buffers[name] = buf
    }

    private func build() {
        var seed: UInt64 = 0x1234567
        func noise() -> Double {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return Double(seed & 0xFFFF) / 32768.0 - 1
        }
        let tau = 2 * Double.pi
        var lp = 0.0

        // Loops (lengths chosen so every sine completes whole cycles).
        make("scrub", seconds: 0.5) { t, _ in
            let n = noise()
            lp += (n - lp) * 0.35
            let stroke = abs(sin(tau * 2 * t))
            return (n - lp) * 0.35 * (0.25 + 0.75 * stroke)
        }
        lp = 0
        make("jet", seconds: 1.0) { t, _ in
            lp += (noise() - lp) * 0.08
            return lp * 1.6 + sin(tau * 90 * t) * 0.05
        }
        lp = 0
        make("engine", seconds: 1.0) { t, _ in
            lp += (noise() - lp) * 0.02
            let a = sin(tau * 48 * t) * 0.3 + sin(tau * 96 * t) * 0.15 + sin(tau * 144 * t) * 0.07
            return a * (0.8 + 0.2 * sin(tau * 6 * t)) + lp * 0.5
        }
        lp = 0
        make("amb", seconds: 4.0) { t, _ in
            lp += (noise() - lp) * 0.01
            let breath = 0.5 + 0.5 * sin(tau * 0.25 * t)
            return sin(tau * 55 * t) * 0.05 + lp * 0.9 * breath
        }

        // One-shots.
        lp = 0
        make("step", seconds: 0.14) { t, _ in
            lp += (noise() - lp) * 0.05
            let env = exp(-t * 38)
            return (sin(tau * 62 * t) * 0.7 + lp * 1.5) * env
        }
        make("click", seconds: 0.06) { t, _ in sin(tau * 1250 * t) * exp(-t * 70) * 0.5 }
        make("deny", seconds: 0.22) { t, _ in
            (sin(tau * 160 * t) > 0 ? 0.25 : -0.25) * exp(-t * 12)
        }
        make("cash", seconds: 0.5) { t, _ in
            let f = t < 0.09 ? 1318.5 : 1975.5
            let local = t < 0.09 ? t : t - 0.09
            return (sin(tau * f * t) * 0.35 + sin(tau * f * 2 * t) * 0.12) * exp(-local * 9)
        }
        lp = 0
        make("pack", seconds: 0.3) { t, _ in
            lp += (noise() - lp) * 0.2
            return sin(tau * (140 - 200 * t) * t) * exp(-t * 16) * 0.7 + lp * exp(-t * 30) * 0.6
        }
        lp = 0
        make("launch", seconds: 1.1) { t, _ in
            lp += (noise() - lp) * (0.03 + 0.2 * t)
            let env = min(1, t * 12) * exp(-t * 2.4)
            return lp * 1.8 * env + sin(tau * (120 + 500 * t) * t) * 0.12 * env
        }
        make("claim", seconds: 0.7) { t, _ in
            let notes: [Double] = [523.25, 659.25, 783.99, 1046.5]
            let k = min(3, Int(t / 0.12))
            let local = t - Double(k) * 0.12
            return sin(tau * notes[k] * t) * 0.3 * exp(-local * 6)
        }
    }

    func start() {
        guard !running else { return }
        build()
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for name in ["scrub", "jet", "engine", "amb"] {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            loops[name] = p
        }
        for _ in 0..<5 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            shots.append(p)
        }
        do {
            try engine.start()
        } catch {
            return
        }
        running = true
        for (name, p) in loops {
            guard let b = buffers[name] else { continue }
            p.volume = 0
            p.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
            p.play()
        }
        shots.forEach { $0.play() }
        engine.mainMixerNode.outputVolume = enabled ? 1 : 0
    }

    func resumeIfNeeded() {
        guard running, !engine.isRunning else { return }
        try? engine.start()
        for (name, p) in loops {
            guard let b = buffers[name] else { continue }
            p.stop()
            p.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
            p.play()
        }
        shots.forEach { $0.play() }
    }

    func setLoop(_ name: String, volume: Float) {
        guard running, let p = loops[name] else { return }
        p.volume += (volume - p.volume) * 0.25
    }

    func play(_ name: String, volume: Float = 1) {
        guard running, enabled, let b = buffers[name] else { return }
        let p = shots[nextShot]
        nextShot = (nextShot + 1) % shots.count
        p.volume = volume
        p.scheduleBuffer(b, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }
}
