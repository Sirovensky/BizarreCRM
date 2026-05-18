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
        guard let id = zReportId, let base = cachedBaseURL else { return nil }
        return base.appendingPathComponent("api/v1/cash-register/z-reports/\(id)/pdf")
    }

    /// Cached server base URL — populated on `loadStats()` so the synchronous
    /// `zReportURL()` getter can run inside the View body.
    public private(set) var cachedBaseURL: URL?

    // MARK: - Init

    public init(api: APIClient, employeeId: Int64) {
        self.api        = api
        self.employeeId = employeeId
    }

    // MARK: - Public interface

    /// Fetches current shift summary from server. Call from `.task { }`.
    public func loadStats() async {
        step = .loadingStats
        cachedBaseURL = await api.currentBaseURL()
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
        // BUGHUNT-2026-05-17: re-entry guard. Without this, a double-tap on
        // "Continue" spawns two parallel submitClose Tasks → duplicate
        // closeShift POSTs and a doubled Z-report row. Only proceed when
        // we're still in the cashCount step.
        guard case .cashCount = step else { return }
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
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: don't paint "Incorrect PIN" on a cancelled
            // verify call — the PIN itself was never checked and the manager
            // would retype a correct PIN thinking they fat-fingered it. Stay
            // on the sign-off step with the PIN field still populated so the
            // caller can re-tap Submit.
            managerPinError = nil
        } catch {
            managerPinError = "Incorrect PIN. Try again."
        }
    }

    // MARK: - Private

    private func submitClose(managerPinVerified: Bool) async {
        guard let existing = summary else { return }
        // BUGHUNT-2026-05-17: re-entry guard against parallel submitClose
        // tasks. If we're already confirming or done, refuse — a second
        // closeShift POST while the first is in flight (or after success)
        // either creates a duplicate close row or corrupts the Z-report id.
        if case .confirming = step { return }
        if case .done = step { return }
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
                _ = try? await api.submitShiftHandoff(employeeId: employeeId, body: handoff)
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
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: closeShift may have already reached the
            // server when the task was cancelled. Painting "Failed: cancelled"
            // tempts a re-submit that would double-close the shift and
            // produce a duplicate Z-report. Roll back to the manager sign-off
            // step (or cashCount if no sign-off needed) so the caller decides
            // how to proceed instead of getting a misleading failure toast.
            step = requiresManagerSignOff ? .managerSignOff : .cashCount
        } catch {
            AppLog.ui.error("EndShift: close failed — \(error.localizedDescription, privacy: .public)")
            step = .failed(error.localizedDescription)
        }
    }
}
