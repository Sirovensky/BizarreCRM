import Foundation
import Core

// MARK: - §39.4 Reconciliation export

/// Generates a CSV export of all transactions + tender splits for a given day.
///
/// The CSV is generated on-device from the local `CashRegisterStore` audit
/// data. The full server-backed export (`GET /pos/reconciliation/daily`) is
/// blocked on server ticket POS-RECON-001. Until then, the local export
/// covers the data the device has witnessed during the shift.
///
/// Row schema:
///   date_time, invoice_id, line_description, qty, unit_price_cents,
///   line_total_cents, tender_method, tender_amount_cents,
///   cashier_id, session_id, notes
public struct ReconciliationCSVGenerator: Sendable {

    public init() {}

    /// Generate a CSV string from a list of transactions.
    /// - Parameter transactions: Sale records from the current or selected shift.
    /// - Returns: UTF-8 CSV string ready for export.
    public func generate(transactions: [ReconciliationRow]) -> String {
        var lines: [String] = [Self.header]
        for row in transactions {
            lines.append(row.csvLine)
        }
        return lines.joined(separator: "\n")
    }

    /// Filename for the exported file. Format: `Reconciliation-YYYY-MM-DD.csv`
    public func filename(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "Reconciliation-\(f.string(from: date)).csv"
    }

    private static let header = [
        "date_time",
        "invoice_id",
        "line_description",
        "qty",
        "unit_price_cents",
        "line_total_cents",
        "tender_method",
        "tender_amount_cents",
        "cashier_id",
        "session_id",
        "notes",
    ].joined(separator: ",")
}

// MARK: - Row model

/// One CSV row representing a single tender split on a sale line.
public struct ReconciliationRow: Sendable, Equatable {
    public let dateTime: Date
    public let invoiceId: Int64
    public let lineDescription: String
    public let qty: Int
    public let unitPriceCents: Int
    public let lineTotalCents: Int
    public let tenderMethod: String
    public let tenderAmountCents: Int
    public let cashierId: Int64?
    public let sessionId: Int64?
    public let notes: String?

    public init(
        dateTime: Date,
        invoiceId: Int64,
        lineDescription: String,
        qty: Int,
        unitPriceCents: Int,
        lineTotalCents: Int,
        tenderMethod: String,
        tenderAmountCents: Int,
        cashierId: Int64? = nil,
        sessionId: Int64? = nil,
        notes: String? = nil
    ) {
        self.dateTime = dateTime
        self.invoiceId = invoiceId
        self.lineDescription = lineDescription
        self.qty = qty
        self.unitPriceCents = unitPriceCents
        self.lineTotalCents = lineTotalCents
        self.tenderMethod = tenderMethod
        self.tenderAmountCents = tenderAmountCents
        self.cashierId = cashierId
        self.sessionId = sessionId
        self.notes = notes
    }

    /// Formatted ISO-8601 timestamp for the CSV row.
    var formattedDateTime: String {
        let f = ISO8601DateFormatter()
        return f.string(from: dateTime)
    }

    var csvLine: String {
        [
            Self.csvEscape(formattedDateTime),
            String(invoiceId),
            Self.csvEscape(lineDescription),
            String(qty),
            String(unitPriceCents),
            String(lineTotalCents),
            Self.csvEscape(tenderMethod),
            String(tenderAmountCents),
            cashierId.map(String.init) ?? "",
            sessionId.map(String.init) ?? "",
            Self.csvEscape(notes ?? ""),
        ].joined(separator: ",")
    }

    /// Escape a value for CSV: wrap in quotes if it contains commas, quotes,
    /// or newlines; escape embedded quotes by doubling.
    static func csvEscape(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n")
        if needsQuotes {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

// MARK: - End-of-day wizard step model

/// §39.4 — End-of-day wizard steps.
///
/// The wizard walks the manager through 7 sequential steps before locking
/// the POS terminal for the night. Each step is stamped in the audit log
/// when completed.
public enum EndOfDayStep: Int, CaseIterable, Sendable, Equatable {
    case closeCashShifts        = 0
    case reviewOpenTickets      = 1
    case sendCustomerSMS        = 2
    case reviewInvoices         = 3
    case backupReminder         = 4
    case lockPOSTerminal        = 5
    case postDailySummary       = 6

    public var title: String {
        switch self {
        case .closeCashShifts:   return "Close cash shifts"
        case .reviewOpenTickets: return "Review open tickets"
        case .sendCustomerSMS:   return "Send status SMS (optional)"
        case .reviewInvoices:    return "Review outstanding invoices"
        case .backupReminder:    return "Backup reminder"
        case .lockPOSTerminal:   return "Lock POS terminal"
        case .postDailySummary:  return "Post daily summary"
        }
    }

    public var subtitle: String {
        switch self {
        case .closeCashShifts:
            return "Close any open cash sessions and verify drawer balances."
        case .reviewOpenTickets:
            return "Mark open tickets ready or archive to tomorrow."
        case .sendCustomerSMS:
            return "Notify customers with ready tickets. SMS opt-out respected."
        case .reviewInvoices:
            return "Check overdue invoices and schedule follow-ups."
        case .backupReminder:
            return "Local backup reminder if tenant schedules manual backups."
        case .lockPOSTerminal:
            return "Lock the POS so no sales can be made until tomorrow."
        case .postDailySummary:
            return "Push daily summary to tenant admin dashboard."
        }
    }

    public var icon: String {
        switch self {
        case .closeCashShifts:   return "lock.open.fill"
        case .reviewOpenTickets: return "ticket.fill"
        case .sendCustomerSMS:   return "message.fill"
        case .reviewInvoices:    return "doc.text.fill"
        case .backupReminder:    return "externaldrive.fill"
        case .lockPOSTerminal:   return "lock.fill"
        case .postDailySummary:  return "chart.bar.fill"
        }
    }

    public var isOptional: Bool {
        self == .sendCustomerSMS || self == .backupReminder
    }
}

// MARK: - End-of-day wizard state

/// Observable state for the `EndOfDayWizardView`.
@MainActor
@Observable
public final class EndOfDayWizardViewModel {

    public enum WizardState: Equatable, Sendable {
        case idle
        case inProgress(step: EndOfDayStep)
        case complete
        case aborted
    }

    private(set) public var completedSteps: Set<EndOfDayStep> = []
    private(set) public var skippedSteps: Set<EndOfDayStep> = []
    private(set) public var wizardState: WizardState = .idle
    private(set) public var csvData: Data?
    private(set) public var csvFilename: String = ""

    private let generator = ReconciliationCSVGenerator()

    public init() {}

    public var canProceed: Bool {
        // All non-optional uncomplete steps must be either done or skipped.
        let required = EndOfDayStep.allCases.filter { !$0.isOptional }
        return required.allSatisfy { completedSteps.contains($0) || skippedSteps.contains($0) }
    }

    public var currentStep: EndOfDayStep? {
        EndOfDayStep.allCases.first {
            !completedSteps.contains($0) && !skippedSteps.contains($0)
        }
    }

    public func markCompleted(_ step: EndOfDayStep) {
        completedSteps.insert(step)
        skippedSteps.remove(step)
        AppLog.pos.info("End-of-day step completed: \(step.title, privacy: .public)")
        advanceIfPossible()
    }

    public func skipStep(_ step: EndOfDayStep) {
        guard step.isOptional else { return }
        skippedSteps.insert(step)
        AppLog.pos.info("End-of-day step skipped: \(step.title, privacy: .public)")
        advanceIfPossible()
    }

    public func abort() {
        wizardState = .aborted
        AppLog.pos.warning("End-of-day wizard aborted")
    }

    /// Generate and cache the CSV export.
    public func generateCSV(transactions: [ReconciliationRow]) {
        let csv = generator.generate(transactions: transactions)
        csvData = csv.data(using: .utf8)
        csvFilename = generator.filename()
    }

    private func advanceIfPossible() {
        if canProceed && currentStep == nil {
            wizardState = .complete
        }
    }
}
