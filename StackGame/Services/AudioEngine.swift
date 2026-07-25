import AVFoundation
import Foundation

/// Procedural audio.
///
/// ## The pentatonic ladder
///
/// This is the hook of the whole genre, and it is worth being explicit about
/// why. Each consecutive perfect placement plays the *next note up* a C minor
/// pentatonic scale; breaking the streak drops back to the root. Players stop
/// chasing the score and start chasing the melody — the sound is the reward, and
/// the score is just its receipt. It is the single highest-leverage thing in the
/// build, which is why it is a first-class system and not polish.
///
/// Every sound is synthesised at launch rather than shipped as assets. Pentatonic
/// steps need exact pitch relationships, and generating them means a perfectly
/// in-tune ladder of any length, a smaller binary, and no licensing questions.
final class AudioEngine {

    private let engine = AVAudioEngine()
    private let players: [AVAudioPlayerNode]
    private var nextPlayer = 0

    private var toneBuffers: [AVAudioPCMBuffer] = []
    private var sliceBuffer: AVAudioPCMBuffer?
    private var gameOverBuffer: AVAudioPCMBuffer?
    private var tierBuffer: AVAudioPCMBuffer?
    private var regrowthBuffer: AVAudioPCMBuffer?

    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    var isMuted = false

    /// C minor pentatonic, in semitones above the root.
    private static let pentatonic = [0, 3, 5, 7, 10]
    /// How many rungs the ladder has before it stops climbing. Past this the
    /// notes would leave the pleasant register and start to grate.
    private static let ladderLength = 16
    private static let rootFrequency = 261.63 // C4

    init() {
        // A small pool, cycled round-robin, so rapid perfects overlap and ring
        // into each other instead of cutting one another off.
        players = (0..<8).map { _ in AVAudioPlayerNode() }

        for player in players {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        buildBuffers()
        configureSession()
        start()
    }

    // MARK: - Session

    private func configureSession() {
        do {
            // `.ambient` respects the ringer switch and mixes with whatever the
            // player already has going. Taking over someone's podcast to play
            // block sounds is not a trade they agreed to.
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Audio is a garnish here. If the session refuses, the game plays on
            // in silence rather than failing to launch.
            assertionFailure("Audio session setup failed: \(error)")
        }
    }

    private func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {
            assertionFailure("Audio engine failed to start: \(error)")
        }
    }

    /// Re-arm after an interruption (a phone call, Siri, a route change).
    func handleInterruptionEnded() {
        try? AVAudioSession.sharedInstance().setActive(true)
        start()
    }

    // MARK: - Playback

    /// Ascend one rung per combo step. `combo` is 1-based.
    func playPerfect(combo: Int) {
        let index = min(max(combo - 1, 0), toneBuffers.count - 1)
        play(toneBuffers[index])
    }

    func playSlice() { play(sliceBuffer) }
    func playGameOver() { play(gameOverBuffer) }
    func playTierCrossing() { play(tierBuffer) }
    func playRegrowth() { play(regrowthBuffer) }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard !isMuted, let buffer, engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Synthesis

    private func buildBuffers() {
        toneBuffers = (0..<Self.ladderLength).map { step in
            let octave = step / Self.pentatonic.count
            let degree = Self.pentatonic[step % Self.pentatonic.count]
            let semitones = Double(degree + octave * 12)
            let frequency = Self.rootFrequency * pow(2, semitones / 12)

            // Higher rungs get shorter and brighter, so a long streak
            // accelerates rather than turning into mud.
            let duration = max(0.28, 0.52 - Double(step) * 0.012)
            return makeTone(
                frequency: frequency,
                duration: duration,
                harmonics: [(1.0, 1.0), (2.0, 0.28), (3.0, 0.10)],
                attack: 0.004,
                decayCurve: 5.5
            )
        }

        sliceBuffer = makeNoise(duration: 0.20, cutoffSweep: (1_400, 180), gain: 0.42)

        gameOverBuffer = makeSweep(
            from: Self.rootFrequency * 0.75,
            to: Self.rootFrequency * 0.32,
            duration: 0.85,
            gain: 0.36
        )

        // Root-fifth-octave: reads as arrival without being a fanfare.
        tierBuffer = makeChord(
            frequencies: [
                Self.rootFrequency,
                Self.rootFrequency * pow(2, 7.0 / 12),
                Self.rootFrequency * 2
            ],
            duration: 1.1,
            gain: 0.30
        )

        regrowthBuffer = makeArpeggio(
            frequencies: Self.pentatonic.map { Self.rootFrequency * 2 * pow(2, Double($0) / 12) },
            noteDuration: 0.09,
            gain: 0.34
        )
    }

    private func makeBuffer(frameCount: Int) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    private func write(_ buffer: AVAudioPCMBuffer, _ sample: (Int, Double) -> Float) {
        let count = Int(buffer.frameLength)
        let rate = format.sampleRate
        guard let channels = buffer.floatChannelData else { return }
        for frame in 0..<count {
            let value = sample(frame, Double(frame) / rate)
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = value
            }
        }
    }

    private func makeTone(
        frequency: Double,
        duration: Double,
        harmonics: [(Double, Double)],
        attack: Double,
        decayCurve: Double
    ) -> AVAudioPCMBuffer {
        let frames = Int(duration * format.sampleRate)
        guard let buffer = makeBuffer(frameCount: frames) else {
            return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        }

        // Hoisted out of the per-sample closure, and written with a named
        // parameter on purpose: `$1.1` inside a shorthand closure is ambiguous —
        // Swift can lex it as the literal 1.1 rather than as the tuple's second
        // element.
        let normalization = harmonics.reduce(0.0) { total, harmonic in total + harmonic.1 }

        write(buffer) { _, time in
            let envelope: Double
            if time < attack {
                envelope = time / attack
            } else {
                envelope = exp(-(time - attack) * decayCurve)
            }

            var value = 0.0
            for (multiple, amplitude) in harmonics {
                value += sin(2 * .pi * frequency * multiple * time) * amplitude
            }
            return Float(value / normalization * envelope * 0.32)
        }
        return buffer
    }

    private func makeChord(frequencies: [Double], duration: Double, gain: Double) -> AVAudioPCMBuffer {
        let frames = Int(duration * format.sampleRate)
        guard let buffer = makeBuffer(frameCount: frames) else {
            return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        }

        write(buffer) { _, time in
            let envelope = time < 0.01 ? time / 0.01 : exp(-(time - 0.01) * 2.2)
            var value = 0.0
            for frequency in frequencies {
                value += sin(2 * .pi * frequency * time)
            }
            return Float(value / Double(frequencies.count) * envelope * gain)
        }
        return buffer
    }

    private func makeArpeggio(
        frequencies: [Double],
        noteDuration: Double,
        gain: Double
    ) -> AVAudioPCMBuffer {
        let total = noteDuration * Double(frequencies.count) + 0.3
        let frames = Int(total * format.sampleRate)
        guard let buffer = makeBuffer(frameCount: frames) else {
            return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        }

        write(buffer) { _, time in
            let index = min(Int(time / noteDuration), frequencies.count - 1)
            let localTime = time - Double(index) * noteDuration
            let envelope = exp(-localTime * 9)
            return Float(sin(2 * .pi * frequencies[index] * time) * envelope * gain)
        }
        return buffer
    }

    /// Filtered noise burst. A one-pole low-pass whose cutoff falls across the
    /// sound gives the dull, woody thud of material being knocked away.
    private func makeNoise(
        duration: Double,
        cutoffSweep: (Double, Double),
        gain: Double
    ) -> AVAudioPCMBuffer {
        let frames = Int(duration * format.sampleRate)
        guard let buffer = makeBuffer(frameCount: frames) else {
            return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        }

        var rng = SystemRandomNumberGenerator()
        var previous = 0.0
        let rate = format.sampleRate

        write(buffer) { _, time in
            let progress = time / duration
            let cutoff = cutoffSweep.0 + (cutoffSweep.1 - cutoffSweep.0) * progress
            let alpha = 1 - exp(-2 * .pi * cutoff / rate)

            let white = Double.random(in: -1...1, using: &rng)
            previous += alpha * (white - previous)

            let envelope = exp(-time * 14)
            return Float(previous * envelope * gain)
        }
        return buffer
    }

    private func makeSweep(
        from startFrequency: Double,
        to endFrequency: Double,
        duration: Double,
        gain: Double
    ) -> AVAudioPCMBuffer {
        let frames = Int(duration * format.sampleRate)
        guard let buffer = makeBuffer(frameCount: frames) else {
            return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        }

        var phase = 0.0
        let step = 1.0 / format.sampleRate

        write(buffer) { _, time in
            let progress = time / duration
            let frequency = startFrequency + (endFrequency - startFrequency) * progress
            phase += 2 * .pi * frequency * step
            let envelope = exp(-time * 2.4)
            let value = sin(phase) * 0.7 + sin(phase * 2) * 0.3
            return Float(value * envelope * gain)
        }
        return buffer
    }
}
