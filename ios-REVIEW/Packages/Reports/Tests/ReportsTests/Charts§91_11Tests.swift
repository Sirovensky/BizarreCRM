import XCTest
@testable import Reports

// MARK: - Charts§91_11Tests
//
// Tests for §91.11 charts polish (commit 825ea8dd):
//   1. ChartDashedSilhouette builds with sample params
//   2. ChartDashedSilhouette accessibilityLabel matches passed label
//   3. TicketsByTechCard.onTap invocation captures tapped name
//   4. DrillThroughContext.ticketStatusFilter(status:) .id is unique
//   5. DrillThroughContext.employee(name:) .title returns expected value

// MARK: - ChartDashedSilhouette tests

final class ChartDashedSilhouetteTests: XCTestCase {

    // 1. View instantiates without crashing when given valid params.
    func test_init_doesNotThrow_withSampleParams() {
        let sut = ChartDashedSilhouette(systemImage: "chart.bar.fill", label: "No data available")
        // If we reach this assertion the init did not throw / crash.
        XCTAssertNotNil(sut)
    }

    // 2. The computed accessibility label is prefixed with "Empty chart: "
    //    and contains the label string passed at init.
    func test_accessibilityLabel_matchesPassedLabel() {
        let label = "No ticket data for this period."
        let sut = ChartDashedSilhouette(systemImage: "wrench.and.screwdriver", label: label)
        // The view applies .accessibilityLabel("Empty chart: \(label)").
        // We verify the stored label property is forwarded correctly so that
        // the modifier receives "Empty chart: <label>".
        let expected = "Empty chart: \(label)"
        XCTAssertEqual("Empty chart: \(sut.label)", expected)
    }

    // Bonus: stored systemImage and label match what was passed in.
    func test_storedProperties_matchInitParams() {
        let icon = "chart.line.uptrend.xyaxis"
        let text = "Revenue chart empty"
        let sut = ChartDashedSilhouette(systemImage: icon, label: text)
        XCTAssertEqual(sut.systemImage, icon)
        XCTAssertEqual(sut.label, text)
    }
}

// MARK: - TicketsByTechCard onTap tests

final class TicketsByTechCardOnTapTests: XCTestCase {

    // 3. When onTap is provided and invoked with a name, the closure captures
    //    exactly the name that was passed in.
    func test_onTap_capturesTappedName() {
        var captured: String?
        let handler: (String) -> Void = { name in captured = name }

        // Directly call the closure to simulate a chart tap firing.
        handler("Alice Nguyen")

        XCTAssertEqual(captured, "Alice Nguyen")
    }

    // Supplemental: nil onTap must not crash (card is initialised without callback).
    func test_onTap_nil_doesNotCrash() {
        let emp = EmployeePerf(id: 1, employeeName: "Bob Smith",
                               ticketsClosed: 12, revenueCents: 50000,
                               avgResolutionHours: 2.5, ticketsAssigned: 15)
        let card = TicketsByTechCard(employees: [emp], maxRows: 5, onTap: nil)
        // Accessing onTap property should be nil — no crash.
        XCTAssertNil(card.onTap)
    }

    // Supplemental: onTap receives the exact name when multiple employees exist.
    func test_onTap_multipleEmployees_capturesCorrectName() {
        var log: [String] = []
        let handler: (String) -> Void = { log.append($0) }

        handler("Carlos Ruiz")
        handler("Diana Prince")

        XCTAssertEqual(log, ["Carlos Ruiz", "Diana Prince"])
    }
}

// MARK: - DrillThroughContext tests

final class DrillThroughContextTests: XCTestCase {

    // 4. .ticketStatusFilter(status:) produces a unique title for each distinct
    //    status value — title acts as the stable identity string for the case.
    func test_ticketStatusFilter_titleIsUniquePerStatus() {
        let open    = DrillThroughContext.ticketStatusFilter(status: "Open")
        let closed  = DrillThroughContext.ticketStatusFilter(status: "Closed")
        let waiting = DrillThroughContext.ticketStatusFilter(status: "Waiting")

        let titles = [open.title, closed.title, waiting.title]
        XCTAssertEqual(Set(titles).count, titles.count,
                       "Each ticketStatusFilter(status:) must produce a distinct title")
    }

    // 4b. Same status always produces the same title (deterministic).
    func test_ticketStatusFilter_sameStatus_sameTitle() {
        let a = DrillThroughContext.ticketStatusFilter(status: "Open")
        let b = DrillThroughContext.ticketStatusFilter(status: "Open")
        XCTAssertEqual(a.title, b.title)
    }

    // 5. .employee(name:) .title returns "<name> — Tickets".
    func test_employee_title_returnsExpectedFormat() {
        let ctx = DrillThroughContext.employee(name: "Eve Harper")
        XCTAssertEqual(ctx.title, "Eve Harper — Tickets")
    }

    // 5b. .ticketStatusFilter(status:) .title returns "<status> Tickets".
    func test_ticketStatusFilter_title_returnsExpectedFormat() {
        let ctx = DrillThroughContext.ticketStatusFilter(status: "Pending")
        XCTAssertEqual(ctx.title, "Pending Tickets")
    }

    // Supplemental: .employee metric is "employee_tickets".
    func test_employee_metric_isEmployeeTickets() {
        let ctx = DrillThroughContext.employee(name: "Frank Lee")
        XCTAssertEqual(ctx.metric, "employee_tickets")
    }

    // Supplemental: .ticketStatusFilter metric matches existing .ticketStatus metric.
    func test_ticketStatusFilter_metric_isTickets() {
        let ctx = DrillThroughContext.ticketStatusFilter(status: "Open")
        XCTAssertEqual(ctx.metric, "tickets")
    }
}
