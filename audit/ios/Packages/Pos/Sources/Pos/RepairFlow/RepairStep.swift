#if canImport(UIKit)
import Foundation

// MARK: - RepairStep
//
// Ordered steps in the POS repair intake flow. Steps correspond 1-to-1 with
// the frames 1b → 1e documented in ios/pos-iphone-mockups.html.

/// The four-step repair intake flow progresses linearly: device picker →
/// symptom capture → diagnostic quote → deposit collection.
///
/// `progressPercent` drives the progress bar visible in every step header.
public enum RepairStep: Int, CaseIterable, Sendable, Equatable {
    /// Frame 1b — Select or scan the customer's device.
    case pickDevice = 0
    /// Frame 1c — Describe the symptom, choose condition, pick quick chips.
    case describeIssue = 1
    /// Frame 1d — Diagnostic notes + parts/labor checklist + running estimate.
    case diagnosticQuote = 2
    /// Frame 1e — Collect deposit (subset of full total) before work begins.
    case deposit = 3

    // MARK: - Progress

    /// Percentage complete shown in the step progress bar (0–100 inclusive).
    public var progressPercent: Double {
        switch self {
        case .pickDevice:     return 25
        case .describeIssue:  return 50
        case .diagnosticQuote: return 75
        case .deposit:        return 100
        }
    }

    // MARK: - Navigation helpers

    /// The step that precedes this one, or `nil` for the first step.
    public var previous: RepairStep? {
        guard rawValue > 0 else { return nil }
        return RepairStep(rawValue: rawValue - 1)
    }

    /// The step that follows this one, or `nil` for the last step.
    public var next: RepairStep? {
        RepairStep(rawValue: rawValue + 1)
    }

    // MARK: - Display

    /// Short title shown in the navigation bar.
    public var navigationTitle: String {
        switch self {
        case .pickDevice:      return "Pick device"
        case .describeIssue:   return "Describe issue"
        case .diagnosticQuote: return "Quote"
        case .deposit:         return "Deposit"
        }
    }

    /// Accessibility description for VoiceOver ("Step 1 of 4 — Pick device").
    public var accessibilityDescription: String {
        "Step \(rawValue + 1) of \(RepairStep.allCases.count) — \(navigationTitle)"
    }
}
#endif
