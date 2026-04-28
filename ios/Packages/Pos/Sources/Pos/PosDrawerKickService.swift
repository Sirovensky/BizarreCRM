import Foundation
import Hardware

// MARK: - PosDrawerKickService

/// Bridges the POS sale-completion flow with the Hardware `CashDrawerManager`.
///
/// Call `kickIfNeeded(tenders:cashierName:)` immediately after `POST /invoices/{id}/payments`
/// succeeds, passing the full set of applied tenders. The service maps each tender to the
/// appropriate `DrawerTriggerTender` and calls `CashDrawerManager.handleTender(_:)`.
///
/// ## §16.8 — Cash drawer kick on cash tender
///
/// The Hardware module owns the low-level ESC/POS kick command; this service
/// is the POS-side orchestrator that decides *when* to fire.
///
/// Only `.cash` and `.check` tenders trigger the drawer by default (matching the
/// `CashDrawerManager.triggerTenders` default set). All other tenders (card, gift
/// card, store credit, etc.) do not open the drawer.
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

    /// Kick the cash drawer if any of the applied tenders require it.
    ///
    /// - Parameters:
    ///   - tenders:      The full set of applied tenders from the completed sale.
    ///   - cashierName:  Passed through to the audit log (defaults to "Cashier").
    public func kickIfNeeded(
        tenders: [AppliedTenderV2],
        cashierName: String = "Cashier"
    ) async {
        let drawerTenders: [DrawerTriggerTender] = tenders.compactMap { applied -> DrawerTriggerTender? in
            switch applied.method {
            case .cash:  return .cash
            case .check: return .check
            default:     return nil
            }
        }

        guard !drawerTenders.isEmpty else { return }

        // Fire once per unique trigger type (e.g. don't double-kick for split cash+check).
        for trigger in Set(drawerTenders) {
            await manager.handleTender(trigger, cashierName: cashierName)
        }
    }
}
