import XCTest
@testable import Expenses

// MARK: - Stubs

private struct SuccessfulRepo: RecurringExpenseRepository {
    let rules: [RecurringExpenseRule]
    let created: RecurringExpenseRule

    func fetchRules() async throws -> [RecurringExpenseRule] { rules }
    func createRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule { created }
    func deleteRule(id: Int64) async throws {}
}

private struct ThrowingRepo: RecurringExpenseRepository {
    let error: Error
    func fetchRules() async throws -> [RecurringExpenseRule] { throw error }
    func createRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule { throw error }
    func deleteRule(id: Int64) async throws { throw error }
}

private struct EmptyRepo: RecurringExpenseRepository {
    func fetchRules() async throws -> [RecurringExpenseRule] { [] }
    func createRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule {
        throw URLError(.unknown)
    }
    func deleteRule(id: Int64) async throws {}
}

// MARK: - Call-counting repo (using class for shared mutable state)

private final class CountingRepo: RecurringExpenseRepository, @unchecked Sendable {
    var fetchCount = 0
    let rule: RecurringExpenseRule

    init(rule: RecurringExpenseRule) { self.rule = rule }

    func fetchRules() async throws -> [RecurringExpenseRule] {
        fetchCount += 1
        return [rule]
    }
    func createRule(_ body: CreateRecurringExpenseBody) async throws -> RecurringExpenseRule { rule }
    func deleteRule(id: Int64) async throws {}
}

// MARK: - Fixtures

private extension RecurringExpenseRule {
    static func fixture(
        id: Int64 = 1,
        merchant: String = "Rent",
        amountCents: Int = 150_000,
        frequency: RecurringFrequency = .monthly,
        dayOfMonth: Int = 1
    ) -> RecurringExpenseRule {
        RecurringExpenseRule(
            id: id,
            merchant: merchant,
            amountCents: amountCents,
            category: "Rent",
            frequency: frequency,
            dayOfMonth: dayOfMonth
        )
    }
}

// MARK: - RecurringExpenseRepositoryTests

final class RecurringExpenseRepositoryTests: XCTestCase {

    // MARK: - Protocol conformance

    func test_liveRecurringExpenseRepository_conformsToProtocol() {
        let _: any RecurringExpenseRepository = LiveRecurringExpenseRepository(api: .shared)
        XCTAssert(true, "LiveRecurringExpenseRepository satisfies RecurringExpenseRepository protocol")
    }

    // MARK: - fetchRules success

    func test_fetchRules_returnsMappedRules() async throws {
        let expected = [RecurringExpenseRule.fixture(merchant: "Lease")]
        let repo = SuccessfulRepo(rules: expected, created: .fixture())
        let rules = try await repo.fetchRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].merchant, "Lease")
    }

    // MARK: - fetchRules failure

    func test_fetchRules_throwsOnError() async {
        let repo = ThrowingRepo(error: URLError(.notConnectedToInternet))
        do {
            _ = try await repo.fetchRules()
            XCTFail("Expected throw")
        } catch let e as URLError {
            XCTAssertEqual(e.code, .notConnectedToInternet)
        }
    }

    // MARK: - createRule

    func test_createRule_returnsServerEntity() async throws {
        let expected = RecurringExpenseRule.fixture(id: 99, merchant: "Electricity")
        let repo = SuccessfulRepo(rules: [], created: expected)
        let body = CreateRecurringExpenseBody(
            merchant: "Electricity",
            amountCents: 8_000,
            category: "Utilities",
            frequency: .monthly,
            dayOfMonth: 15,
            notes: nil
        )
        let created = try await repo.createRule(body)
        XCTAssertEqual(created.id, 99)
        XCTAssertEqual(created.merchant, "Electricity")
    }

    // MARK: - deleteRule (no-throw path)

    func test_deleteRule_succeeds() async {
        let repo = SuccessfulRepo(rules: [], created: .fixture())
        // Should not throw
        do {
            try await repo.deleteRule(id: 42)
        } catch {
            XCTFail("deleteRule should not throw: \(error)")
        }
    }

    // MARK: - RecurringExpenseRunner via stub repo

    func test_runner_nextOccurrenceLabel_nilWhenNoRules() async {
        let runner = RecurringExpenseRunner(repository: EmptyRepo())
        let label = await runner.nextOccurrenceLabel()
        XCTAssertNil(label, "No rules → no label")
    }

    func test_runner_nextOccurrenceLabel_containsMerchant() async throws {
        let rule = RecurringExpenseRule.fixture(merchant: "Insurance", dayOfMonth: 5)
        let repo = SuccessfulRepo(rules: [rule], created: .fixture())
        let runner = RecurringExpenseRunner(repository: repo)
        let label = await runner.nextOccurrenceLabel()
        XCTAssertNotNil(label, "Rule present → label returned")
        XCTAssertTrue(label?.contains("Insurance") == true,
                      "Label should contain merchant; got: \(label ?? "nil")")
    }

    func test_runner_fetchRules_cachesResultsForSubsequentNextOccurrence() async throws {
        let rule = RecurringExpenseRule.fixture()
        let repo = CountingRepo(rule: rule)
        let runner = RecurringExpenseRunner(repository: repo)

        _ = try await runner.fetchRules()      // sets lastFetchedAt
        _ = await runner.nextOccurrenceLabel() // refreshIfNeeded → skips because lastFetchedAt < 300s

        XCTAssertEqual(repo.fetchCount, 1,
                       "Repository should only be called once due to 5-min cache window")
    }

    func test_runner_fetchRulesThrows_returnsNilLabel() async {
        let repo = ThrowingRepo(error: URLError(.notConnectedToInternet))
        let runner = RecurringExpenseRunner(repository: repo)
        let label = await runner.nextOccurrenceLabel() // refreshIfNeeded swallows error
        XCTAssertNil(label, "Failed fetch → nil label (not a crash)")
    }

    func test_runner_createRule_delegatesToRepo() async throws {
        let expected = RecurringExpenseRule.fixture(id: 77)
        let repo = SuccessfulRepo(rules: [], created: expected)
        let runner = RecurringExpenseRunner(repository: repo)
        let body = CreateRecurringExpenseBody(
            merchant: "SaaS Tool",
            amountCents: 4_900,
            category: "Software",
            frequency: .monthly,
            dayOfMonth: 1,
            notes: nil
        )
        let created = try await runner.createRule(body)
        XCTAssertEqual(created.id, 77)
    }

    func test_runner_deleteRule_delegatesToRepo() async throws {
        let repo = SuccessfulRepo(rules: [], created: .fixture())
        let runner = RecurringExpenseRunner(repository: repo)
        // Should not throw
        do {
            try await runner.deleteRule(id: 5)
        } catch {
            XCTFail("deleteRule should propagate without error: \(error)")
        }
    }

    // MARK: - RecurringExpenseRule model

    func test_rule_nextOccurrenceLabelMonthly() {
        let rule = RecurringExpenseRule.fixture(merchant: "Rent", frequency: .monthly, dayOfMonth: 1)
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let midMonth = cal.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let label = rule.nextOccurrenceLabel(relativeTo: midMonth)
        XCTAssertTrue(label.hasPrefix("Rent on"), "Expected 'Rent on ...'; got '\(label)'")
    }

    func test_rule_nextOccurrenceLabelYearly() {
        let rule = RecurringExpenseRule.fixture(merchant: "Insurance", frequency: .yearly, dayOfMonth: 1)
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let midYear = cal.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let label = rule.nextOccurrenceLabel(relativeTo: midYear)
        XCTAssertTrue(label.contains("Insurance"), "Label should contain merchant")
    }

    func test_rule_amountDollars_convertsFromCents() {
        let rule = RecurringExpenseRule.fixture(amountCents: 99_99)
        XCTAssertEqual(rule.amountDollars, 99.99, accuracy: 0.001)
    }

    // MARK: - CreateRecurringExpenseBody encoding

    func test_createBody_encodesCodingKeys() throws {
        let body = CreateRecurringExpenseBody(
            merchant: "Lease",
            amountCents: 200_000,
            category: "Rent",
            frequency: .yearly,
            dayOfMonth: 1,
            notes: "Annual"
        )
        let data = try JSONEncoder().encode(body)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(dict["amount_cents"],  "snake_case key required")
        XCTAssertNotNil(dict["day_of_month"],  "snake_case key required")
        XCTAssertNil(dict["amountCents"],      "camelCase must not appear")
        XCTAssertNil(dict["dayOfMonth"],       "camelCase must not appear")
        XCTAssertEqual(dict["frequency"] as? String, "yearly")
    }

    func test_createBody_fromExistingRule_preservesFields() throws {
        let rule = RecurringExpenseRule.fixture(merchant: "Parking", amountCents: 2_000, dayOfMonth: 10)
        let body = CreateRecurringExpenseBody(rule: rule)
        let data = try JSONEncoder().encode(body)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["merchant"] as? String, "Parking")
        XCTAssertEqual(dict["amount_cents"] as? Int, 2_000)
        XCTAssertEqual(dict["day_of_month"] as? Int, 10)
    }

    // MARK: - RecurringFrequency display

    func test_recurringFrequency_displayNames() {
        XCTAssertEqual(RecurringFrequency.monthly.displayName, "Monthly")
        XCTAssertEqual(RecurringFrequency.yearly.displayName, "Yearly")
    }

    func test_recurringFrequency_allCasesCount() {
        XCTAssertEqual(RecurringFrequency.allCases.count, 2)
    }
}
