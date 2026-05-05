import Foundation
import Persistence

/// §39 — ViewModel that drives `CloseRegisterSheet` and the Z-report flow.
///
/// Responsibilities:
///  1. Fetch live register state (`GET /pos/register`) to compute expected cash.
///  2. Accept the cashier's counted-cash input.
///  3. Derive variance and band from `CashVariance`.
///  4. Enforce red-band notes requirement before allowing commit.
///  5. Call `CashSessionRepository.closeSession` and expose the closed record
///     so `ZReportView` can be presented inline.
///
/// No UIKit dependency — fully testable in a headless XCTest target.
@Observable
@MainActor
public final class CloseRegisterViewModel {

    // MARK: - Input state

    /// Text bound to the "Counted cash" field.
    public var countedText: String = ""

    /// Optional notes from the cashier.
    public var notes: String = ""

    // MARK: - Output state

    /// `true` while fetching register state or closing the session.
    public private(set) var isLoading: Bool = false

    /// `true` while the close call is in flight.
    public private(set) var isSubmitting: Bool = false

    /// Error surfaced to the UI. Cleared on each new action.
    public private(set) var errorMessage: String?

    /// Loaded from `GET /pos/register` — expected cash = net (float + sales - moves).
    public private(set) var expectedCents: Int = 0

    /// Set after successful close — drives ZReport presentation.
    public private(set) var closedSession: CashSessionRecord?

    // MARK: - Dependencies

    private let session: CashSessionRecord
    private let closedBy: Int64
    private let repository: CashSessionRepository

    // MARK: - Init

    public init(
        session: CashSessionRecord,
        closedBy: Int64,
        repository: CashSessionRepository
    ) {
        self.session = session
        self.closedBy = closedBy
        self.repository = repository
        // Seed expected from local opening float until server data arrives.
        self.expectedCents = session.openingFloat
    }

    // MARK: - Derived

    /// Cents from `countedText`, zero if unparseable or negative input.
    public var countedCents: Int {
        let trimmed = countedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value >= 0 else { return 0 }
        return CartMath.toCents(value)
    }

    /// Variance = countedCents - expectedCents.
    public var varianceCents: Int { countedCents - expectedCents }

    /// Variance classification — drives color coding and notes requirement.
    public var varianceBand: CashVariance.Band { CashVariance.band(cents: varianceCents) }

    /// Whether the Close CTA is enabled.
    public var canSubmit: Bool {
        let trimmed = countedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return CashVariance.canCommit(varianceCents: varianceCents, notes: notes)
    }

    /// Notes are required when variance is in the red band.
    public var notesRequired: Bool { CashVariance.notesRequired(cents: varianceCents) }

    // MARK: - Actions

    /// Load live expected-cash figure from the server.
    /// Expected = opening float + server net (captures cash-ins, cash-outs, cash sales).
    public func loadRegisterState() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await repository.fetchRegisterState()
            // Server `net` = cashIn + cashSales - cashOut (already includes opening float
            // for today via the cash_register table). Add the session's opening float so
            // the expected figure is relative to what should be physically in the drawer.
            expectedCents = session.openingFloat + state.cashSales + state.cashIn - state.cashOut
        } catch {
            // Non-fatal: we fall back to the local opening float seed.
            // Log for debugging but don't block the close flow.
            errorMessage = "Could not fetch register totals — using local estimate."
        }
    }

    /// Close the session. On success `closedSession` is set.
    public func close() async {
        guard !isSubmitting, canSubmit else {
            if !canSubmit {
                errorMessage = notesRequired
                    ? "Notes are required for a variance greater than $5."
                    : "Enter the counted cash amount."
            }
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let record = try await repository.closeSession(
                countedCash: countedCents,
                expectedCash: expectedCents,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                closedBy: closedBy
            )
            closedSession = record
        } catch CashRegisterError.noOpenSession {
            errorMessage = "No open session — reopen the register before closing."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Dismiss a transient error (e.g. the server-fetch warning).
    public func clearError() { errorMessage = nil }
}
