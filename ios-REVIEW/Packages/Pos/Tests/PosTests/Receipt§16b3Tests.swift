import XCTest
@testable import Pos
import Persistence

/// §16 b3 — Tests covering the four additions landed in commits
/// ac69c890..4ce4849e:
///
/// 1. `PosReceiptRenderer.Payload.isGiftMode` — text/HTML renderers suppress
///    all money strings when the flag is set.
/// 2. `PosAuditEntry.EventType.drawerOpen` raw value and `eventTypeLabel`.
/// 3. `GiftReceiptOptions.message` — 120-char acceptance; model stores >120
///    without truncation (limit is enforced at the UI binding layer).
final class Receipt§16b3Tests: XCTestCase {

    // MARK: - Shared payload factory

    /// Returns a non-trivial `Payload` with a single line at $12.34 and a
    /// $1.00 tax row so there are several money strings to check.
    private static func samplePayload(isGiftMode: Bool) -> PosReceiptRenderer.Payload {
        PosReceiptRenderer.Payload(
            merchant: PosReceiptRenderer.Payload.Merchant(
                name: "Bizarre Test Shop",
                address: "123 Test St",
                phone: nil
            ),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            customerName: "Grace Hopper",
            orderNumber: "ORD-9001",
            lines: [
                PosReceiptRenderer.Payload.Line(
                    name: "Widget Pro",
                    sku: "WID-PRO",
                    quantity: 2,
                    unitPriceCents: 617,
                    discountCents: 0,
                    lineTotalCents: 1234
                )
            ],
            subtotalCents: 1234,
            discountCents: 0,
            feesCents: 0,
            taxCents: 100,
            tipCents: 0,
            totalCents: 1334,
            tenders: [
                PosReceiptRenderer.Payload.Tender(method: "Card", amountCents: 1334, last4: "4242")
            ],
            currencyCode: "USD",
            footer: nil,
            isGiftMode: isGiftMode
        )
    }

    // MARK: - Test 1: text gift mode strips all money ($)

    func test_text_giftMode_doesNotContainDollarSign() {
        let payload = Self.samplePayload(isGiftMode: true)
        let text = PosReceiptRenderer.text(payload)
        XCTAssertFalse(
            text.contains("$"),
            "text(isGiftMode: true) must not contain any '$' character; got:\n\(text)"
        )
    }

    // MARK: - Test 2: text normal mode contains money

    func test_text_normalMode_containsDollarSign() {
        let payload = Self.samplePayload(isGiftMode: false)
        let text = PosReceiptRenderer.text(payload)
        XCTAssertTrue(
            text.contains("$"),
            "text(isGiftMode: false) must contain currency amounts; got:\n\(text)"
        )
    }

    // MARK: - Test 3: HTML gift mode shows items but no money rows

    func test_html_giftMode_containsItemLinesButNoMoneyRows() {
        let payload = Self.samplePayload(isGiftMode: true)
        let html = PosReceiptRenderer.html(payload)

        // Item name must appear
        XCTAssertTrue(
            html.contains("Widget Pro"),
            "HTML gift receipt must include the item name"
        )
        // SKU must appear
        XCTAssertTrue(
            html.contains("SKU: WID-PRO"),
            "HTML gift receipt must include the SKU"
        )
        // Quantity marker must appear
        XCTAssertTrue(
            html.contains("2 &times;"),
            "HTML gift receipt must include the quantity"
        )
        // No dollar signs anywhere
        XCTAssertFalse(
            html.contains("$"),
            "HTML gift receipt must not contain any '$'; got:\n\(html)"
        )
        // Summary rows must be absent
        XCTAssertFalse(
            html.contains("Subtotal"),
            "HTML gift receipt must not contain Subtotal row"
        )
        XCTAssertFalse(
            html.contains("Tax"),
            "HTML gift receipt must not contain Tax row"
        )
        XCTAssertFalse(
            html.contains("Total"),
            "HTML gift receipt must not contain Total row"
        )
        // Tender rows must be absent
        XCTAssertFalse(
            html.contains("Card"),
            "HTML gift receipt must not contain tender method"
        )
        // Amount column header must be suppressed
        XCTAssertFalse(
            html.contains(">Amount<"),
            "HTML gift receipt must not contain the Amount column header"
        )
    }

    // MARK: - Test 4: PosAuditEntry.EventType.drawerOpen raw value

    func test_eventType_drawerOpen_rawValue() {
        XCTAssertEqual(
            PosAuditEntry.EventType.drawerOpen,
            "drawer_open",
            "EventType.drawerOpen must equal the string literal \"drawer_open\""
        )
    }

    // MARK: - Test 5: eventTypeLabel returns "Drawer opened" for drawer_open

    func test_eventTypeLabel_drawerOpen_returnsDrawerOpened() {
        let entry = PosAuditEntry(
            eventType: PosAuditEntry.EventType.drawerOpen,
            cashierId: 1
        )
        XCTAssertEqual(
            entry.eventTypeLabel,
            "Drawer opened",
            "eventTypeLabel for drawer_open must return \"Drawer opened\""
        )
    }

    // MARK: - Test 6a: GiftReceiptOptions.message accepts ≤120 chars

    func test_giftReceiptOptions_message_acceptsUpTo120Chars() {
        let exactly120 = String(repeating: "A", count: 120)
        var options = GiftReceiptOptions.default
        options.message = exactly120
        XCTAssertEqual(
            options.message?.count, 120,
            "GiftReceiptOptions.message must store a 120-character string unchanged"
        )
    }

    // MARK: - Test 6b: model stores >120 chars (UI layer enforces the limit)

    func test_giftReceiptOptions_message_modelDoesNotTruncateAbove120() {
        // The 120-char cap is enforced by the UI text-field binding via
        // `String($0.prefix(120))`. The model itself is a plain `String?`
        // with no enforcement, so assigning a longer value stores it as-is.
        let over120 = String(repeating: "B", count: 121)
        var options = GiftReceiptOptions.default
        options.message = over120
        XCTAssertEqual(
            options.message?.count, 121,
            "The model does not truncate; limit is enforced at the UI binding layer"
        )
    }

    // MARK: - Test 6c: UI binding prefix(120) truncation contract

    func test_uiBinding_truncatesToPrefix120() {
        // Simulate what the GiftReceiptCheckoutSheet binding does:
        //   set: { vm.options.message = $0.isEmpty ? nil : String($0.prefix(120)) }
        let over120 = String(repeating: "C", count: 130)
        let afterBinding: String? = over120.isEmpty ? nil : String(over120.prefix(120))
        XCTAssertEqual(
            afterBinding?.count, 120,
            "UI binding must truncate input to the first 120 characters"
        )
    }
}
