import Foundation
import Core

// MARK: - §36.4 Setup wizard metrics (telemetry placeholders)

/// Tracks per-step completion rate, time-in-step, and drop-off for the
/// Setup Wizard.
///
/// **Privacy:** All events are PII-redacted per §32.6. Entity IDs are hashed;
/// no raw company name, address, email, or user name is ever included in an
/// event payload.
///
/// **Implementation:** Stubs for now — metrics routed to `AppLog.ui` only.
/// Wire to tenant-analytics endpoint when §32 telemetry pipeline ships.
public final class SetupMetrics: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = SetupMetrics()

    // MARK: - Step entry timestamps (in-process only, not persisted)

    private var stepEntryTimes: [Int: Date] = [:]
    private let lock = NSLock()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Record that the user entered `step`. Starts the time-in-step clock.
    public func stepEntered(_ stepNumber: Int) {
        lock.withLock { stepEntryTimes[stepNumber] = Date() }
        AppLog.ui.info(
            "Setup: entered step \(stepNumber, privacy: .public)"
        )
    }

    /// Record that the user completed `step`. Emits a completion event with
    /// elapsed time-in-step (seconds, rounded).
    public func stepCompleted(_ stepNumber: Int) {
        let elapsed: TimeInterval? = lock.withLock {
            guard let entered = stepEntryTimes.removeValue(forKey: stepNumber) else { return nil }
            return Date().timeIntervalSince(entered)
        }
        let elapsedStr = elapsed.map { "\(Int($0.rounded()))s" } ?? "unknown"
        AppLog.ui.info(
            "Setup: completed step \(stepNumber, privacy: .public) in \(elapsedStr, privacy: .public)"
        )
        // TODO(§32 telemetry): route to analytics endpoint with:
        // { event: "setup.step.completed", step: stepNumber, elapsed_seconds: Int(elapsed) }
    }

    /// Record that the user skipped `step` without submitting.
    public func stepSkipped(_ stepNumber: Int) {
        let elapsed: TimeInterval? = lock.withLock {
            guard let entered = stepEntryTimes.removeValue(forKey: stepNumber) else { return nil }
            return Date().timeIntervalSince(entered)
        }
        let elapsedStr = elapsed.map { "\(Int($0.rounded()))s" } ?? "unknown"
        AppLog.ui.info(
            "Setup: skipped step \(stepNumber, privacy: .public) after \(elapsedStr, privacy: .public)"
        )
        // TODO(§32 telemetry): route to analytics endpoint with:
        // { event: "setup.step.skipped", step: stepNumber, elapsed_seconds: Int(elapsed ?? 0) }
    }

    /// Record that the user dropped off (deferred wizard) at `step`.
    /// This is the primary metric for identifying funnel exit points.
    public func wizardDeferred(atStep stepNumber: Int, completedSteps: Set<Int>) {
        lock.withLock { stepEntryTimes.removeAll() }
        let completedCount = completedSteps.count
        AppLog.ui.info(
            "Setup: deferred at step \(stepNumber, privacy: .public), completed=\(completedCount, privacy: .public)"
        )
        // TODO(§32 telemetry): route to analytics endpoint with:
        // { event: "setup.wizard.deferred", drop_off_step: stepNumber, completed_count: completedCount }
    }

    /// Record that the wizard completed successfully.
    public func wizardCompleted(completedSteps: Set<Int>) {
        lock.withLock { stepEntryTimes.removeAll() }
        AppLog.ui.info(
            "Setup: wizard completed, total steps done=\(completedSteps.count, privacy: .public)"
        )
        // TODO(§32 telemetry): route to analytics endpoint with:
        // { event: "setup.wizard.completed", step_count: completedSteps.count }
    }
}

// MARK: - SetupWizardViewModel + metrics integration

/// Extension on `SetupWizardViewModel` to plug `SetupMetrics` into existing
/// navigation hooks.
///
/// Call from `SetupWizardView` on each step transition:
/// ```swift
/// .onChange(of: vm.currentStep) { old, new in
///     SetupMetrics.shared.stepEntered(new.rawValue)
/// }
/// ```
public extension SetupMetrics {
    /// Convenience that fires on every step change observed from the view.
    func onStepChange(from old: Int, to new: Int) {
        // The "old" step is implicitly done if we moved forward, skipped if we
        // jumped over it. For metrics purposes, just record entry of the new step.
        _ = old // suppress unused warning
        stepEntered(new)
    }
}
