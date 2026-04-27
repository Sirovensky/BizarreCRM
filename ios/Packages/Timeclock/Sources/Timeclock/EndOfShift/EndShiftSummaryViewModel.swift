import Foundation
import Observation
import Networking
import Core

/// §14.10 — End-of-shift summary view model.
///
/// Drives a multi-step cashier close-out flow:
///   1. Fetch live shift stats from server.
///   2. Cashier counts cash by denomination.
///   3. Compute over/short live.
///   4. If |over/short| > $2 → require manager PIN + reason.
///   5. Submit close; optionally store handoff amount for next opener.
@MainActor
@Observable
public final class EndShiftSummaryViewModel {

    // MARK: - State

    public enum Step: Equatable, Sendable {
        case loadingStats
        case summaryReview              // review sales KPIs before cash count
        case cashCount                  // denomination entry
        case managerSignOff             // shown only when requiresManagerSignOff
        case confirming                 // submitting to server
        case done(Int64)                // shiftId from server
        case failed(String)
    }

    public private(set) var step: Step = .loadingStats
    public private(set) var summary: EndShiftSummary?

    /// Z-report ID returned by the server on shift close (`EndShiftResponse.zReportId`).
    /// Non-nil when the tenant has the Z-report feature enabled and the report was
    /// archived server-side.  Used by the done screen to surface a "View Z-Report" link.
    public private(set) var zReportId: Int64?

    /// Denomination rows the cashier fills in.
    public var denominations: [CashDenomination] = CashDenomination.defaultDenominations

    /// Over/short reason — required when |over/short| > $2.
    public var overShortReason: String = ""

    /// Manager PIN entered during sign-off step; cleared after submission.
    public var managerPin: String = ""
    public private(set) var managerPinError: String?
    public private(set) var managerPinVerified: Bool = false

    /// Opening cash that closing cashier passes to next session.
    public var handoffCashCents: Int = 0

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let employeeId: Int64
    private let calculator = OverShortCalculator()

    // MARK: - Z-report URL helper

    /// Returns the authenticated PDF URL for the Z-report, constructed from the
    /// tenant's `baseURL`.  Returns nil when `zReportId` is nil or baseURL is unset.
    public func zReportURL() -> URL? {
        guard let id = zReportId,
              let base = api.currentBaseURL() else { return nil }
        return base.appendingPathComponent("api/v1/cash-register/z-reports/\(id)/pdf")
    }

    // MARK: - Init

    public init(api: APIClient, employeeId: Int64) {
        self.api        = api
        self.employeeId = employeeId
    }

    // MARK: - Public interface

    /// Fetches current shift summary from server. Call from `.task { }`.
    public func loadStats() async {
        step = .loadingStats
        do {
            let dto = try await api.getCurrentShiftSummary(employeeId: employeeId)
            let stub = EndShiftSummary(
                salesCount: dto.salesCount,
                grossCents: dto.grossCents,
                tipsCents: dto.tipsCents,
                cashExpectedCents: dto.cashExpectedCents,
                cashCountedCents: 0,   // filled after denomination count
                itemsSold: dto.itemsSold,
                voidCount: dto.voidCount
            )
            summary = stub
            step = .summaryReview
        } catch {
            AppLog.ui.error("EndShift: stats load failed — \(error.localizedDescription, privacy: .public)")
            step = .failed(error.localizedDescription)
        }
    }

    /// Advance from summary review to cash count entry.
    public func proceedToCashCount() {
        step = .cashCount
    }

    /// Computed from denomination counts vs server-expected amount.
    public var liveCountedCents: Int {
        denominations.reduce(0) { $0 + $1.totalCents }
    }

    public var liveOverShortCents: Int {
        liveCountedCents - (summary?.cashExpectedCents ?? 0)
    }

    public var requiresManagerSignOff: Bool { abs(liveOverShortCents) > 200 }

    /// Called when cashier taps "Continue" in cash-count step.
    public func finishCashCount() {
        if requiresManagerSignOff {
            step = .managerSignOff
        } else {
            Task { await submitClose(managerPinVerified: false) }
        }
    }

    /// Called after manager enters PIN on sign-off screen.
    public func verifyManagerPin() async {
        managerPinError = nil
        guard !managerPin.isEmpty else {
            managerPinError = "Please enter the manager PIN."
            return
        }
        do {
            // Reuse the existing verifyPin endpoint used by clock-in gate.
            // Server: POST /auth/verify-pin { user_id, pin }
            // We pass 0 for userId since any manager-role PIN is accepted;
            // server resolves the role check on its side.
            _ = try await api.verifyPin(userId: 0, pin: managerPin)
            managerPinVerified = true
            managerPin = ""
            await submitClose(managerPinVerified: true)
        } catch {
            managerPinError = "Incorrect PIN. Try again."
        }
    }

    // MARK: - Private

    private func submitClose(managerPinVerified: Bool) async {
        guard let existing = summary else { return }
        step = .confirming
        let request = EndShiftRequest(
            cashCountedCents: liveCountedCents,
            overShortCents: liveOverShortCents,
            overShortReason: requiresManagerSignOff ? overShortReason : nil,
            managerPinVerified: managerPinVerified
        )
        do {
            let response = try await api.closeShift(employeeId: employeeId, body: request)

            // Capture Z-report ID if the server archived a report (§39 feature).
            zReportId = response.zReportId

            // Store handoff amount for next opener if cashier chose to enter one.
            if handoffCashCents > 0 {
                let handoff = ShiftHandoffRequest(openingCashCents: handoffCashCents)
                try? await api.submitShiftHandoff(employeeId: employeeId, body: handoff)
            }

            // Update local summary with final counts for the done screen.
            summary = EndShiftSummary(
                salesCount: existing.salesCount,
                grossCents: existing.grossCents,
                tipsCents: existing.tipsCents,
                cashExpectedCents: existing.cashExpectedCents,
                cashCountedCents: liveCountedCents,
                itemsSold: existing.itemsSold,
                voidCount: existing.voidCount
            )
            step = .done(response.shiftId)
        } catch {
            AppLog.ui.error("EndShift: close failed — \(error.localizedDescription, privacy: .public)")
            step = .failed(error.localizedDescription)
        }
    }
}
