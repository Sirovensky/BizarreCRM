import XCTest
@testable import Invoices

// §7.8 RecurringInvoiceRule model + editor VM tests

final class RecurringInvoiceRuleTests: XCTestCase {

    // MARK: - RecurringInvoiceRule model

    func test_init_dayOfMonthClamped_low() {
        let rule = makeRule(dayOfMonth: -5)
        XCTAssertEqual(rule.dayOfMonth, 1)
    }

    func test_init_dayOfMonthClamped_high() {
        let rule = makeRule(dayOfMonth: 31)
        XCTAssertEqual(rule.dayOfMonth, 28)
    }

    func test_init_dayOfMonth_valid() {
        let rule = makeRule(dayOfMonth: 15)
        XCTAssertEqual(rule.dayOfMonth, 15)
    }

    func test_frequency_allCasesHaveDisplayNames() {
        for freq in RecurringFrequency.allCases {
            XCTAssertFalse(freq.displayName.isEmpty, "Frequency \(freq.rawValue) missing display name")
        }
    }

    func test_frequency_idEqualsRawValue() {
        for freq in RecurringFrequency.allCases {
            XCTAssertEqual(freq.id, freq.rawValue)
        }
    }

    func test_codingRoundTrip() throws {
        let rule = makeRule(dayOfMonth: 14)
        let encoded = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RecurringInvoiceRule.self, from: encoded)
        XCTAssertEqual(decoded.id, rule.id)
        XCTAssertEqual(decoded.customerId, rule.customerId)
        XCTAssertEqual(decoded.frequency, rule.frequency)
        XCTAssertEqual(decoded.dayOfMonth, rule.dayOfMonth)
        XCTAssertEqual(decoded.autoSend, rule.autoSend)
    }

    func test_autoSend_defaultFalse() {
        let rule = makeRule()
        XCTAssertFalse(rule.autoSend)
    }

    func test_endDate_nilByDefault() {
        let rule = makeRule()
        XCTAssertNil(rule.endDate)
    }

    func test_name_nilByDefault() {
        let rule = makeRule()
        XCTAssertNil(rule.name)
    }

    // MARK: - Editor VM

    @MainActor
    func test_editorVM_defaultFrequency_isMonthly() {
        let vm = makeEditorVM()
        XCTAssertEqual(vm.frequency, .monthly)
    }

    @MainActor
    func test_editorVM_defaultDayOfMonth_is1() {
        let vm = makeEditorVM()
        XCTAssertEqual(vm.dayOfMonth, 1)
    }

    @MainActor
    func test_editorVM_isValid_withNilCustomerId_false() {
        let vm = makeEditorVM()
        vm.customerId = nil
        vm.templateInvoiceId = 1
        XCTAssertFalse(vm.isValid)
    }

    @MainActor
    func test_editorVM_isValid_withNilTemplateId_false() {
        let vm = makeEditorVM()
        vm.customerId = 1
        vm.templateInvoiceId = nil
        XCTAssertFalse(vm.isValid)
    }

    @MainActor
    func test_editorVM_isValid_withBothSet_true() {
        let vm = makeEditorVM()
        vm.customerId = 1
        vm.templateInvoiceId = 5
        XCTAssertTrue(vm.isValid)
    }

    @MainActor
    func test_editorVM_prefillsFromExistingRule() {
        let rule = makeRule(dayOfMonth: 20)
        let vm = RecurringInvoiceEditorViewModel(api: StubAPIClient(), rule: rule)
        XCTAssertEqual(vm.frequency, rule.frequency)
        XCTAssertEqual(vm.dayOfMonth, 20)
        XCTAssertEqual(vm.autoSend, rule.autoSend)
    }

    // MARK: - CreateRecurringRuleRequest

    func test_createRequest_codingKeys() throws {
        let req = CreateRecurringRuleRequest(
            customerId: 42,
            templateInvoiceId: 7,
            frequency: .quarterly,
            dayOfMonth: 1,
            startDate: "2024-01-01",
            endDate: nil,
            autoSend: true,
            name: "Quarterly billing"
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["customer_id"] as? Int, 42)
        XCTAssertEqual(json["template_invoice_id"] as? Int, 7)
        XCTAssertEqual(json["frequency"] as? String, "quarterly")
        XCTAssertEqual(json["auto_send"] as? Bool, true)
        XCTAssertEqual(json["name"] as? String, "Quarterly billing")
    }

    // MARK: - Helpers

    private func makeRule(dayOfMonth: Int = 1) -> RecurringInvoiceRule {
        RecurringInvoiceRule(
            id: 1,
            customerId: 10,
            templateInvoiceId: 5,
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            nextRunAt: Date(timeIntervalSince1970: 0),
            startDate: Date(timeIntervalSince1970: 0)
        )
    }

    @MainActor
    private func makeEditorVM() -> RecurringInvoiceEditorViewModel {
        RecurringInvoiceEditorViewModel(api: StubAPIClient())
    }
}
