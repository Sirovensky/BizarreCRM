import AppIntents
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §24.4 ScanBarcodeIntent — opens scanner → inventory lookup or POS add-to-cart

/// App Intent that launches the barcode scanner.
///
/// Siri / Shortcuts usage:
///   - "Scan a barcode in Bizarre CRM"
///   - "Open scanner in Bizarre CRM"
///   - "Scan inventory item in Bizarre CRM"
///
/// On iPhone: opens the camera barcode scanner.
/// On Mac/iPad without camera: opens the manual entry field (§23.1 gating).
///
/// Destination after scan is controlled by the `destination` parameter:
///   - `inventory` (default) — look up or create an inventory item.
///   - `pos` — add the scanned item directly to the active POS cart.
///   - `ticket` — attach the scanned device serial to an open ticket.
@available(iOS 16.0, *)
struct AppShellScanBarcodeIntent: AppIntent {

    // MARK: - AppIntent metadata

    static let title: LocalizedStringResource = "Scan Barcode"
    static let description: IntentDescription = IntentDescription(
        "Open the BizarreCRM barcode scanner to look up inventory, add items to a sale, or link a device serial to a ticket.",
        categoryName: "Inventory"
    )
    static let isDiscoverable: Bool = true
    static let openAppWhenRun: Bool = true

    // MARK: - Parameters

    @Parameter(
        title: "Destination",
        description: "What to do after scanning the barcode.",
        default: ScanDestination.inventory
    )
    var destination: ScanDestination

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let path: String
        switch destination {
        case .inventory: path = "bizarrecrm://inventory/scan"
        case .pos:       path = "bizarrecrm://pos/scan"
        case .ticket:    path = "bizarrecrm://tickets/scan"
        }
        await openURL(path)
        return .result(dialog: scanDialog)
    }

    private var scanDialog: IntentDialog {
        switch destination {
        case .inventory: return "Opening barcode scanner for inventory lookup."
        case .pos:       return "Opening barcode scanner to add an item to the sale."
        case .ticket:    return "Opening barcode scanner to link a device to a ticket."
        }
    }
}

// MARK: - ScanDestination

@available(iOS 16.0, *)
enum ScanDestination: String, AppEnum, Sendable {
    case inventory = "inventory"
    case pos       = "pos"
    case ticket    = "ticket"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Scan Destination")
    }

    static var caseDisplayRepresentations: [ScanDestination: DisplayRepresentation] {
        [
            .inventory: DisplayRepresentation(
                title: "Inventory",
                subtitle: "Look up or create an inventory item"
            ),
            .pos: DisplayRepresentation(
                title: "POS Cart",
                subtitle: "Add the scanned item to the current sale"
            ),
            .ticket: DisplayRepresentation(
                title: "Ticket",
                subtitle: "Link the scanned device serial to an open ticket"
            )
        ]
    }
}

// MARK: - Shortcuts phrase registration

@available(iOS 16.0, *)
enum BizarreCRMScanBarcodeShortcuts {
    @AppShortcutsBuilder
    static var shortcuts: [AppShortcut] {
        AppShortcut(
            intent: AppShellScanBarcodeIntent(),
            phrases: [
                "Scan barcode in \(.applicationName)",
                "Open scanner in \(.applicationName)",
                "Scan inventory in \(.applicationName)",
                "Scan item in \(.applicationName)"
            ],
            shortTitle: "Scan Barcode",
            systemImageName: "barcode.viewfinder"
        )
        AppShortcut(
            intent: {
                var i = AppShellScanBarcodeIntent()
                i.destination = .pos
                return i
            }(),
            phrases: [
                "Scan item for sale in \(.applicationName)",
                "Add scanned item to cart in \(.applicationName)"
            ],
            shortTitle: "Scan for POS",
            systemImageName: "cart.badge.plus"
        )
    }
}

// MARK: - URL helper

@MainActor
private func openURL(_ urlString: String) async {
    #if canImport(UIKit)
    guard let url = URL(string: urlString) else { return }
    await UIApplication.shared.open(url)
    #endif
}
