import CoreHaptics
import UIKit

/// Haptics, mapped one-to-one onto the audio events.
///
/// Every pattern has a `UIFeedbackGenerator` fallback. Core Haptics is absent on
/// iPad and on older iPhones, and a `nil` engine there must degrade to a plain
/// tap rather than to nothing.
final class HapticsEngine {

    enum Event {
        case perfect
        case slice
        case milestone
        case regrowth
        case gameOver
    }

    var isEnabled = true

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    init() {
        prepareGenerators()
        guard supportsHaptics else { return }

        do {
            let engine = try CHHapticEngine()
            // The system stops the engine when the app backgrounds or after an
            // audio interruption; without these it silently never comes back.
            engine.stoppedHandler = { [weak self] _ in
                self?.engine = nil
            }
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    private func prepareGenerators() {
        lightImpact.prepare()
        rigidImpact.prepare()
        heavyImpact.prepare()
        notification.prepare()
    }

    func play(_ event: Event) {
        guard isEnabled else { return }
        guard supportsHaptics, let engine else {
            playFallback(event)
            return
        }

        do {
            let pattern = try pattern(for: event)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            playFallback(event)
        }
    }

    private func playFallback(_ event: Event) {
        switch event {
        case .perfect: rigidImpact.impactOccurred(intensity: 0.9)
        case .slice: lightImpact.impactOccurred(intensity: 0.6)
        case .milestone: notification.notificationOccurred(.success)
        case .regrowth: notification.notificationOccurred(.success)
        case .gameOver: heavyImpact.impactOccurred(intensity: 1.0)
        }
    }

    private func pattern(for event: Event) throws -> CHHapticPattern {
        switch event {
        case .perfect:
            // Sharp and short. A perfect should feel like a click, not a thump.
            return try CHHapticPattern(events: [
                transient(intensity: 0.95, sharpness: 0.95, at: 0)
            ], parameters: [])

        case .slice:
            // Duller and softer, so failure is unmistakably a different texture
            // from success even without looking at the screen.
            return try CHHapticPattern(events: [
                transient(intensity: 0.55, sharpness: 0.25, at: 0)
            ], parameters: [])

        case .milestone:
            return try CHHapticPattern(events: [
                transient(intensity: 0.7, sharpness: 0.6, at: 0),
                transient(intensity: 0.9, sharpness: 0.8, at: 0.09)
            ], parameters: [])

        case .regrowth:
            return try CHHapticPattern(events: [
                transient(intensity: 0.6, sharpness: 0.7, at: 0),
                transient(intensity: 0.75, sharpness: 0.8, at: 0.06),
                transient(intensity: 1.0, sharpness: 0.95, at: 0.13)
            ], parameters: [])

        case .gameOver:
            return try CHHapticPattern(events: [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: 0,
                    duration: 0.42
                )
            ], parameters: [])
        }
    }

    private func transient(intensity: Float, sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }
}
