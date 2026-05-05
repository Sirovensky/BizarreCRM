import XCTest
@testable import Core

// §31.8 Parameterized fixture tests
//
// Demonstrates the fixture-driven parameterized testing pattern for BizarreCRM.
// Each fixture file maps to a typed struct; shared domain invariants are asserted
// against every fixture in a single loop rather than per-file test methods.
//
// Why: §31.8 requires "Parameterized tests using fixtures" so that adding a new
// fixture JSON automatically exercises all shared invariants without new test code.

// MARK: - Fixture model definitions (test-local)

/// Minimal Decodable ticket — subset of the production model.
private struct FixtureTicket: Decodable {
    let id: Int
    let number: String
    let title: String
    let status: String
    let priority: String
    let customerId: Int
    let laborCents: Int
    let createdAt: Date
    let updatedAt: Date
}

/// Minimal Decodable inventory item — subset of the production model.
private struct FixtureInventoryItem: Decodable {
    let id: Int
    let sku: String
    let name: String
    let quantityOnHand: Int
    let lowStockThreshold: Int
    let costCents: Int
    let retailCents: Int
    let taxable: Bool
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Ticket fixture tests

final class TicketFixtureTests: XCTestCase {

    private func loader() -> FixtureLoader { FixtureLoader(bundle: .module) }

    // MARK: §31.8 ticket_default invariants

    func test_ticketDefault_loadsWithoutError() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertEqual(ticket.id, 101, "id must match fixture")
        XCTAssertEqual(ticket.number, "TK-0101", "ticket number must match fixture")
    }

    func test_ticketDefault_statusIsNonEmpty() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertFalse(ticket.status.isEmpty, "status must not be empty")
    }

    func test_ticketDefault_priorityIsNonEmpty() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertFalse(ticket.priority.isEmpty, "priority must not be empty")
    }

    func test_ticketDefault_laborCentsIsNonNegative() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertGreaterThanOrEqual(ticket.laborCents, 0, "laborCents must be ≥ 0")
    }

    func test_ticketDefault_customerIdIsPositive() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertGreaterThan(ticket.customerId, 0, "customerId must reference a valid customer")
    }

    func test_ticketDefault_createdAtBeforeUpdatedAt_orEqual() throws {
        let ticket: FixtureTicket = try loader().load("ticket_default")
        XCTAssertLessThanOrEqual(
            ticket.createdAt, ticket.updatedAt,
            "createdAt must not be after updatedAt"
        )
    }

    // MARK: §31.8 Parameterized invariant sweep
    //
    // Extend this array as new ticket fixtures are added; every invariant below
    // is automatically applied to every fixture name in the list.

    private let allTicketFixtureNames: [String] = [
        "ticket_default",
    ]

    func test_allTicketFixtures_idIsPositive() throws {
        let loader = loader()
        for name in allTicketFixtureNames {
            let ticket: FixtureTicket = try loader.load(name)
            XCTAssertGreaterThan(ticket.id, 0, "\(name): id must be > 0")
        }
    }

    func test_allTicketFixtures_titleIsNonEmpty() throws {
        let loader = loader()
        for name in allTicketFixtureNames {
            let ticket: FixtureTicket = try loader.load(name)
            XCTAssertFalse(ticket.title.isEmpty, "\(name): title must not be empty")
        }
    }

    func test_allTicketFixtures_numberStartsWithTK() throws {
        let loader = loader()
        for name in allTicketFixtureNames {
            let ticket: FixtureTicket = try loader.load(name)
            XCTAssertTrue(
                ticket.number.hasPrefix("TK-"),
                "\(name): ticket number '\(ticket.number)' must start with 'TK-'"
            )
        }
    }
}

// MARK: - Inventory fixture tests

final class InventoryFixtureTests: XCTestCase {

    private func loader() -> FixtureLoader { FixtureLoader(bundle: .module) }

    // MARK: §31.8 inventory_item_default invariants

    func test_inventoryItemDefault_loadsWithoutError() throws {
        let item: FixtureInventoryItem = try loader().load("inventory_item_default")
        XCTAssertEqual(item.id, 501)
        XCTAssertEqual(item.sku, "SCRN-IP14P-BLK")
    }

    func test_inventoryItemDefault_costLessThanRetail() throws {
        let item: FixtureInventoryItem = try loader().load("inventory_item_default")
        XCTAssertLessThan(
            item.costCents, item.retailCents,
            "cost must be less than retail price for healthy margin"
        )
    }

    func test_inventoryItemDefault_quantityIsNonNegative() throws {
        let item: FixtureInventoryItem = try loader().load("inventory_item_default")
        XCTAssertGreaterThanOrEqual(item.quantityOnHand, 0)
    }

    func test_inventoryItemDefault_lowStockThresholdIsPositive() throws {
        let item: FixtureInventoryItem = try loader().load("inventory_item_default")
        XCTAssertGreaterThan(item.lowStockThreshold, 0,
            "lowStockThreshold must be > 0 so alerts can fire")
    }

    func test_inventoryItemDefault_skuMatchesSKUPattern() throws {
        // SKU rule: uppercase alphanumeric + hyphens, ≥3 chars
        let item: FixtureInventoryItem = try loader().load("inventory_item_default")
        let skuPattern = #"^[A-Z0-9][A-Z0-9\-]{2,}$"#
        let regex = try NSRegularExpression(pattern: skuPattern)
        let range = NSRange(item.sku.startIndex..., in: item.sku)
        XCTAssertNotNil(
            regex.firstMatch(in: item.sku, range: range),
            "SKU '\(item.sku)' must match pattern \(skuPattern)"
        )
    }

    // MARK: §31.8 Parameterized sweep

    private let allInventoryFixtureNames: [String] = [
        "inventory_item_default",
    ]

    func test_allInventoryFixtures_idIsPositive() throws {
        let loader = loader()
        for name in allInventoryFixtureNames {
            let item: FixtureInventoryItem = try loader.load(name)
            XCTAssertGreaterThan(item.id, 0, "\(name): id must be > 0")
        }
    }

    func test_allInventoryFixtures_nameIsNonEmpty() throws {
        let loader = loader()
        for name in allInventoryFixtureNames {
            let item: FixtureInventoryItem = try loader.load(name)
            XCTAssertFalse(item.name.isEmpty, "\(name): name must not be empty")
        }
    }

    func test_allInventoryFixtures_retailCentsIsPositive() throws {
        let loader = loader()
        for name in allInventoryFixtureNames {
            let item: FixtureInventoryItem = try loader.load(name)
            XCTAssertGreaterThan(item.retailCents, 0, "\(name): retailCents must be > 0")
        }
    }
}
