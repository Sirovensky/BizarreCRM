import Foundation
import Hardware
import Persistence

// MARK: - PosDrawerKickService

/// Bridges the POS sale-completion flow with the Hardware `CashDrawerManager`.
///
/// Call `kickIfNeeded(tenders:cashierName:cashierId:)` immediately after
/// `POST /invoices/{id}/payments` succeeds, passing the full set of applied
/// tenders. The service maps each tender to the appropriate `DrawerTriggerTender`,
/// calls `CashDrawerManager.handleTender(_:)`, and appends a `drawer_open` entry
/// to `PosAuditLogStore` for loss-prevention reporting.
///
/// ## §16.8 / §16.11 — Cash drawer kick + audit on cash tender
///
/// The Hardware module owns the low-level ESC/POS kick command; this service
/// is the POS-side orchestrator that decides *when* to fire and records every
/// kick attempt for the shift audit log.
///
/// Only `.cash` and `.check` tenders trigger the drawer by default (matching the
/// `CashDrawerManager.triggerTenders` default set). All other tenders (card, gift
/// card, store credit, etc.) do not open the drawer and are not audited here.
///
/// ## Wiring
/// Inject `CashDrawerManager` via Factory DI:
/// ```swift
/// @Injected(\.cashDrawerManager) private var drawerManager: CashDrawerManager
/// let kickService = PosDrawerKickService(manager: drawerManager)
/// await kickService.kickIfNeeded(tenders: appliedTenders, cashierName: session.cashierName)
/// ```
public actor PosDrawerKickService {

    private let manager: CashDrawerManager

    public init(manager: CashDrawerManager) {
        self.manager = manager
    }

    /// Kick the cash drawer if any of the applied tenders require it, and
    /// record a `drawer_open` audit entry for every kick that fires.
    ///
    /// - Parameters:
    ///   - tenders:     The full set of applied tenders from the completed sale.
    ///   - cashierName: Passed through to the hardware kick (defaults to "Cashier").
    ///   - cashierId:   Stored in the audit entry; 0 until auth/me ships.
    public func kickIfNeeded(
        tenders: [AppliedTenderV2],
        cashierName: String = "Cashier",
        cashierId: Int64 = 0
    ) async {
        let drawerTenders: [DrawerTriggerTender] = tenders.compactMap { applied -> DrawerTriggerTender? in
            switch applied.method {
            case .cash:  return .cash
            case .check: return .check
            default:     return nil
            }
        }

        guard !drawerTenders.isEmpty else { return }

        // Build a human-readable trigger summary for the audit log reason field
        // (e.g. "cash" or "cash, check").
        let triggerNames = tenders
            .filter { $0.method == .cash || $0.method == .check }
            .map { $0.method.apiValue }
            .uniqued()
            .joined(separator: ", ")

        // Fire once per unique trigger type (e.g. don't double-kick for split cash+check).
        for trigger in Set(drawerTenders) {
            await manager.handleTender(trigger, cashierName: cashierName)
        }

        // §16.11 — record every drawer kick in the audit log so the Z-report
        // loss-prevention tile can surface unexpected opens.
        // Fire-and-forget: never block the sale-completion flow on an audit write.
        Task {
            try? await PosAuditLogStore.shared.record(
                event: PosAuditEntry.EventType.drawerOpen,
                cashierId: cashierId,
                reason: triggerNames
            )
        }
    }
}

// MARK: - Private helpers

private extension Array where Element: Hashable {
    /// Returns the array with consecutive and non-consecutive duplicates removed
    /// while preserving original order. Used to deduplicate tender method names
    /// for the audit reason string without requiring `import Algorithms`.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
