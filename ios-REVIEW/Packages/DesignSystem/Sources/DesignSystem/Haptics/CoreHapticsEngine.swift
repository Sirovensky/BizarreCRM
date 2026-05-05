import Foundation
#if canImport(CoreHaptics)
import CoreHaptics
#endif
#if canImport(UIKit)
import UIKit
#endif

// §66.1 + §66.2 — CoreHaptics engine wrapper
// Single long-lived engine; restarted on audio-session interruption
// and applicationWillEnterForeground. Custom patterns per §66.2.

// MARK: - CoreHapticsEngine

/// Actor-isolated CoreHaptics engine. Safe to call from any concurrency domain.
///
/// `play(event:)` returns `true` if a CoreHaptics pattern was played,
/// `false` if the device does not support haptics or the engine is unavailable
/// (caller should fall back to UIKit feedback).
public actor CoreHapticsEngine {

    // MARK: Shared instance

    public static let shared = CoreHapticsEngine()

    // MARK: Private state

#if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private var isEngineRunning: Bool = false
#endif

    // MARK: Init

    private init() {
        Task { await registerNotifications() }
    }

    // MARK: Public API

    /// Play a custom pattern for `event`. Returns `true` on success.
    public func play(event: HapticEvent) async -> Bool {
#if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return false
        }
        await ensureEngineRunning()
        guard let engine else { return false }

        do {
            let pattern = try makePattern(for: event)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
#else
        return false
#endif
    }

    // MARK: Engine lifecycle

    /// Starts the engine if not already running.
    public func start() async {
#if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if engine == nil {
            do {
                let e = try CHHapticEngine()
                e.stoppedHandler = { [weak self] reason in
                    guard let self else { return }
                    Task { await self.handleEngineStopped(reason: reason) }
                }
                e.resetHandler = { [weak self] in
                    guard let self else { return }
                    Task { await self.restartEngine() }
                }
                engine = e
            } catch {
                return
            }
        }
        await startEngine()
#endif
    }

    // MARK: Private helpers

#if canImport(CoreHaptics)
    private func ensureEngineRunning() async {
        if !isEngineRunning {
            await start()
        }
    }

    private func startEngine() async {
        guard let engine, !isEngineRunning else { return }
        do {
            try await engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
        }
    }

    private func restartEngine() async {
        isEngineRunning = false
        await startEngine()
    }

    private func handleEngineStopped(reason: CHHapticEngine.StoppedReason) {
        isEngineRunning = false
    }

    // MARK: - Pattern factory (§66.2)

    private func makePattern(for event: HapticEvent) throws -> CHHapticPattern {
        switch event {

        case .saleComplete:
            // 3-tap crescendo (0.1 → 0.2 → 0.4 intensity, 40ms apart)
            return try crescendoPattern(intensities: [0.1, 0.2, 0.4], interval: 0.04)

        case .cardDeclined:
            // Two-tap sharp (0.9, 0.9, 80ms apart)
            return try twoTapPattern(intensity: 0.9, interval: 0.08)

        case .drawerKick:
            // Single medium thump
            return try singleTapPattern(intensity: 0.7, sharpness: 0.5)

        case .scanSuccess:
            // Single gentle click
            return try singleTapPattern(intensity: 0.4, sharpness: 0.8)

        case .scanFail:
            // Double sharp warning
            return try twoTapPattern(intensity: 0.8, interval: 0.06)

        case .ticketStatusChange:
            // Ramp 0.2 → 0.6 over 150ms
            return try rampPattern(startIntensity: 0.2, endIntensity: 0.6, duration: 0.15)

        case .signatureCommit:
            // Triple subtle, low intensity
            return try crescendoPattern(intensities: [0.2, 0.2, 0.2], interval: 0.05)

        case .addToCart, .longPressMenu, .swipeActionCommit:
            return try singleTapPattern(intensity: 0.5, sharpness: 0.6)

        case .validationError:
            return try singleTapPattern(intensity: 0.8, sharpness: 0.9)

        case .destructiveConfirm, .swipeActionCommit:
            return try singleTapPattern(intensity: 0.95, sharpness: 0.5)

        case .saveForm, .clockIn, .clockOut:
            return try singleTapPattern(intensity: 0.6, sharpness: 0.7)

        case .pullToRefresh, .toggle, .tabSwitch:
            return try singleTapPattern(intensity: 0.35, sharpness: 0.9)

        // §30 — UI-interaction semantic events
        case .buttonTap:
            // Crisp, low-intensity click — confirms the press without fanfare.
            return try singleTapPattern(intensity: 0.30, sharpness: 0.95)

        case .sheetPresented:
            // Medium thump to mark the sheet landing.
            return try singleTapPattern(intensity: 0.55, sharpness: 0.60)

        case .listItemAppear:
            // Barely perceptible — repeated per row, so must stay subtle.
            return try singleTapPattern(intensity: 0.15, sharpness: 0.80)

        case .cardHoverActivate:
            // Soft click for pointer enter on iPad.
            return try singleTapPattern(intensity: 0.20, sharpness: 0.85)

        case .drawerOpen:
            return try singleTapPattern(intensity: 0.55, sharpness: 0.60)

        case .successConfirm:
            return try singleTapPattern(intensity: 0.60, sharpness: 0.70)

        case .errorShake:
            return try singleTapPattern(intensity: 0.80, sharpness: 0.90)
        }
    }

    // MARK: Pattern builders

    private func singleTapPattern(intensity: Float, sharpness: Float) throws -> CHHapticPattern {
        let tap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: [tap], parameters: [])
    }

    private func twoTapPattern(intensity: Float, interval: TimeInterval) throws -> CHHapticPattern {
        let tap1 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            ],
            relativeTime: 0
        )
        let tap2 = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            ],
            relativeTime: interval
        )
        return try CHHapticPattern(events: [tap1, tap2], parameters: [])
    }

    private func crescendoPattern(intensities: [Float], interval: TimeInterval) throws -> CHHapticPattern {
        let events = intensities.enumerated().map { (index, intensity) in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: Double(index) * interval
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private func rampPattern(
        startIntensity: Float,
        endIntensity: Float,
        duration: TimeInterval
    ) throws -> CHHapticPattern {
        let continuous = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: startIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0,
            duration: duration
        )
        let ramp = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: startIntensity),
                CHHapticParameterCurve.ControlPoint(relativeTime: duration, value: endIntensity)
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: [continuous], parameterCurves: [ramp])
    }
#endif

    // MARK: - Notification registration

    private func registerNotifications() {
        Task { @MainActor in
#if canImport(UIKit)
            // UIApplication notifications are UIKit-only (iOS / tvOS).
            nonisolated(unsafe) let obs1 = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                Task { await self.restartEngineIfNeeded() }
            }
            _ = obs1
#endif
#if canImport(AVFoundation) && !os(macOS)
            nonisolated(unsafe) let obs2 = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                Task { await self.restartEngineIfNeeded() }
            }
            _ = obs2
#endif
        }
    }

    private func restartEngineIfNeeded() async {
#if canImport(CoreHaptics)
        if !isEngineRunning {
            await start()
        }
#endif
    }
}

// MARK: - AVAudioSession import shim
// AVAudioSession is UIKit-only. Guard so macOS/Linux builds don't break.
#if canImport(AVFoundation)
import AVFoundation
#else
// Provide a stub so the notification name compiles on non-Apple platforms.
enum AVAudioSession {
    static let interruptionNotification = Notification.Name("AVAudioSessionInterruptionNotification")
}
#endif
