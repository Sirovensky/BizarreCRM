import Foundation
import Observation
import Core
import Networking

/// §16 Reprint — state machine for reprinting a past receipt.
///
/// **Reprint state machine:**
/// `.idle` → `beginReprint()` → `.selectingReason` → user picks reason
/// → `confirmReprint(reason:)` → `.reprinting` → `.done` or `.error(…)`.
///
/// **Audit:** every reprint logs `POST /sales/:id/reprint-event` so the
/// shrinkage team can flag patterns of unusual reprint volume.
/// API calls go through `ReprintRepository` (§20 containment).
@MainActor
@Observable
public final class ReprintViewModel {

    // MARK: - Reprint reason

    public enum ReprintReason: String, CaseIterable, Identifiable, Sendable {
        case customerAsked    = "customer_asked"
        case damagedOriginal  = "damaged_original"
        case audit            = "audit"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .customerAsked:   return "Customer Asked"
            case .damagedOriginal: return "Damaged Original"
            case .audit:           return "Audit"
            }
        }

        public var systemImage: String {
            switch self {
            case .customerAsked:   return "person.fill.questionmark"
            case .damagedOriginal: return "exclamationmark.triangle"
            case .audit:           return "lock.doc"
            }
        }
    }

    // MARK: - Phase

    public enum Phase: Equatable {
        case idle
        case selectingReason
        case reprinting
        case done
        case error(String)
    }

    // MARK: - State

    public private(set) var phase: Phase = .idle
    public var selectedReason: ReprintReason? = nil
    public let sale: SaleRecord

    // MARK: - Dependencies

    private let repository: any ReprintRepository
    private let onDispatchPrintJob: (PosReceiptRenderer.Payload) -> Void

    // MARK: - Init

    /// Designated init — accepts any `ReprintRepository` (live or test double).
    public init(
        sale: SaleRecord,
        repository: any ReprintRepository,
        onDispatchPrintJob: @escaping (PosReceiptRenderer.Payload) -> Void
    ) {
        self.sale               = sale
        self.repository         = repository
        self.onDispatchPrintJob = onDispatchPrintJob
    }

    /// Convenience init accepting a live `APIClient`.
    public convenience init(
        sale: SaleRecord,
        api: APIClient,
        onDispatchPrintJob: @escaping (PosReceiptRenderer.Payload) -> Void
    ) {
        self.init(
            sale: sale,
            repository: ReprintRepositoryImpl(api: api),
            onDispatchPrintJob: onDispatchPrintJob
        )
    }

    // MARK: - State transitions

    /// Open the reason picker sheet.
    public func beginReprint() {
        guard phase == .idle else { return }
        phase = .selectingReason
    }

    /// Cancel back to idle.
    public func cancelReprint() {
        phase = .idle
        selectedReason = nil
    }

    /// Execute the reprint with the chosen reason. Dispatches the print job
    /// locally, then fires the audit log POST to the server.
    public func confirmReprint(reason: ReprintReason) {
        guard phase == .selectingReason else { return }
        selectedReason = reason
        phase = .reprinting

        Task { [weak self] in
            guard let self else { return }
            do {
                // Build receipt payload from the stored sale record.
                let payload = buildPrintPayload(from: sale)
                // Dispatch the local print job (caller provides the closure).
                self.onDispatchPrintJob(payload)
                // Log reprint event server-side.
                try await logReprintEvent(saleId: sale.id, reason: reason)
                self.phase = .done
                AppLog.pos.info("ReprintVM: reprinted sale \(self.sale.id, privacy: .private), reason=\(reason.rawValue, privacy: .public)")
            } catch {
                let message = (error as? AppError)?.localizedDescription ?? error.localizedDescription
                self.phase = .error(message)
                AppLog.pos.error("ReprintVM: reprint failed — \(message, privacy: .public)")
            }
        }
    }

    // MARK: - Private helpers

    /// Reconstruct a `PosReceiptRenderer.Payload` from the stored `SaleRecord`.
    private func buildPrintPayload(from sale: SaleRecord) -> PosReceiptRenderer.Payload {
        let lines = sale.lines.map { line in
            PosReceiptRenderer.Payload.Line(
                name: line.name,
                sku: line.sku,
                quantity: line.quantity,
                unitPriceCents: line.unitPriceCents,
                discountCents: line.discountCents,
                lineTotalCents: line.lineTotalCents
            )
        }
        let tenders = sale.tenders.map { t in
            PosReceiptRenderer.Payload.Tender(
                method: t.method,
                amountCents: t.amountCents,
                last4: t.last4
            )
        }
        return PosReceiptRenderer.Payload(
            merchant: PosReceiptRenderer.Payload.Merchant(name: "BizarreCRM"),
            date: sale.date,
            customerName: sale.customerName,
            orderNumber: sale.receiptNumber,
            lines: lines,
            subtotalCents: sale.subtotalCents,
            discountCents: sale.discountCents,
            feesCents: sale.feesCents,
            taxCents: sale.taxCents,
            tipCents: sale.tipCents,
            totalCents: sale.totalCents,
            tenders: tenders,
            currencyCode: sale.currencyCode,
            footer: "REPRINT"
        )
    }

    /// Server-side audit log via `ReprintRepository`. Non-fatal — if it fails we
    /// log and swallow because the customer already has the printed receipt.
    private func logReprintEvent(saleId: Int64, reason: ReprintReason) async throws {
        try await repository.logReprintEvent(saleId: saleId, reason: reason.rawValue)
    }
}
