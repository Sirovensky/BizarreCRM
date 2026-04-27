import XCTest
@testable import Estimates
import Networking
import Core

// MARK: - EstimateFromLeadTests (§8.3)
//
// Verifies prefill behaviour when creating an estimate from a lead.

@MainActor
final class EstimateFromLeadTests: XCTestCase {

    // MARK: - Helpers

    private func makeLeadDetail(
        id: Int64 = 1,
        customerId: Int64? = 99,
        firstName: String? = "Alice",
        lastName: String? = "Smith",
        orderId: String? = "LEAD-001"   // for convenience; LeadDetail has no orderId field
    ) -> LeadDetail {
        let customerIdValue = customerId.map { String($0) } ?? "null"
        let json = """
        {
            "id":\(id),
            "first_name":"\(firstName ?? "")",
            "last_name":"\(lastName ?? "")",
            "email":"alice@example.com",
            "phone":"+15005551234",
            "status":"new",
            "lead_score":75,
            "source":"web",
            "customer_id":\(customerIdValue),
            "devices":[],
            "appointments":[]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(LeadDetail.self, from: json)
    }

    private func makeLead(
        id: Int64 = 1,
        firstName: String? = "Alice",
        lastName: String? = "Smith",
        orderId: String? = "LEAD-001"
    ) -> Lead {
        Lead(
            id: id,
            orderId: orderId,
            firstName: firstName,
            lastName: lastName
        )
    }

    // MARK: - Prefill from LeadDetail (§8.3 main path)

    func testPrefillFromLeadDetail_setsCustomerId() {
        let lead = makeLeadDetail(customerId: 42)
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        XCTAssertEqual(vm.customerId, 42)
    }

    func testPrefillFromLeadDetail_setsCustomerDisplayName() {
        let lead = makeLeadDetail(firstName: "Bob", lastName: "Jones")
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        XCTAssertTrue(vm.customerDisplayName.contains("Bob"), "Display name should include first name")
        XCTAssertTrue(vm.customerDisplayName.contains("Jones"), "Display name should include last name")
    }

    func testPrefillFromLeadDetail_notesContainLeadId() {
        let lead = makeLeadDetail(id: 99, orderId: "LEAD-007")
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        XCTAssertTrue(vm.notes.contains("99"), "Notes should mention the source lead ID")
    }

    func testPrefillFromLeadDetail_validUntilIsNotEmpty() {
        let lead = makeLeadDetail()
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        XCTAssertFalse(vm.validUntil.isEmpty, "validUntil should be pre-filled ~30 days out")
    }

    func testPrefillFromLeadDetail_validUntilMatchesYYYYMMDD() {
        let lead = makeLeadDetail()
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        let pattern = #"^\d{4}-\d{2}-\d{2}$"#
        XCTAssertTrue(vm.validUntil.range(of: pattern, options: .regularExpression) != nil,
                      "validUntil '\(vm.validUntil)' should be YYYY-MM-DD")
    }

    func testPrefillFromLeadDetail_noLineItemsPreloaded() {
        let lead = makeLeadDetail()
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        XCTAssertTrue(vm.lineItems.isEmpty, "Line items should be empty — customer adds them manually")
    }

    func testPrefillFromLeadDetail_nilCustomerId_setsNilCustomerId() {
        let lead = makeLeadDetail(customerId: nil)
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        XCTAssertNil(vm.customerId)
    }

    func testPrefillFromLeadDetail_isValidTrueWithCustomerId() {
        let lead = makeLeadDetail(customerId: 5)
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        XCTAssertTrue(vm.isValid)
    }

    func testPrefillFromLeadDetail_isValidFalseWithoutCustomerId() {
        let lead = makeLeadDetail(customerId: nil)
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        XCTAssertFalse(vm.isValid)
    }

    func testPrefillFromLeadDetail_currentDraftCaptures() {
        let lead = makeLeadDetail(customerId: 10, firstName: "Carol", lastName: "White")
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLeadDetail: lead)
        let draft = vm.currentDraft()
        XCTAssertEqual(draft.customerId, "10")
        XCTAssertFalse(draft.validUntil.isEmpty)
    }

    // MARK: - Prefill from Lead summary (§8.3 fallback path)

    func testPrefillFromLead_customerIdIsNil() {
        let lead = makeLead(firstName: "Dave", lastName: "Brown")
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLead: lead)
        XCTAssertNil(vm.customerId, "Lead summary has no customerId — user must pick customer")
    }

    func testPrefillFromLead_customerDisplayNameSetFromLead() {
        let lead = makeLead(firstName: "Dave", lastName: "Brown")
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLead: lead)
        XCTAssertTrue(vm.customerDisplayName.contains("Dave"), "Should carry lead name to display")
    }

    func testPrefillFromLead_validUntilNotEmpty() {
        let lead = makeLead()
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLead: lead)
        XCTAssertFalse(vm.validUntil.isEmpty)
    }

    func testPrefillFromLead_isInvalidWithoutCustomer() {
        let lead = makeLead()
        let vm = EstimateCreateViewModel(api: StubAPIClient(), prefillFromLead: lead)
        XCTAssertFalse(vm.isValid, "No customerId → invalid until user selects one")
    }
}
