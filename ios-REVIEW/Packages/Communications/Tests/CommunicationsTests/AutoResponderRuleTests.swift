import XCTest
@testable import Communications

final class AutoResponderRuleTests: XCTestCase {

    // MARK: - matches(message:)

    func test_matches_caseSensitive_false() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["STOP", "Unsubscribe"],
            reply: "You have been unsubscribed.", enabled: true
        )
        XCTAssertTrue(rule.matches(message: "stop"))
        XCTAssertTrue(rule.matches(message: "STOP"))
        XCTAssertTrue(rule.matches(message: "unsubscribe"))
        XCTAssertTrue(rule.matches(message: "Please UNSUBSCRIBE me"))
    }

    func test_noMatch_whenKeywordAbsent() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["STOP"],
            reply: "Unsubscribed.", enabled: true
        )
        XCTAssertFalse(rule.matches(message: "Hello there"))
    }

    func test_disabled_neverMatches() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["STOP"],
            reply: "Unsubscribed.", enabled: false
        )
        XCTAssertFalse(rule.matches(message: "stop"))
    }

    func test_emptyTriggers_neverMatches() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: [],
            reply: "Reply.", enabled: true
        )
        XCTAssertFalse(rule.matches(message: "anything"))
    }

    // MARK: - isActive(at:)

    func test_noTimeWindow_alwaysActive() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["HI"],
            reply: "Hello!", enabled: true,
            startTime: nil, endTime: nil
        )
        XCTAssertTrue(rule.isActive(at: Date()))
    }

    func test_withinTimeWindow_isActive() {
        // Window 08:00 – 20:00; test at 10:00
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["HI"],
            reply: "Hello!", enabled: true,
            startTime: timeComponents(hour: 8, minute: 0),
            endTime: timeComponents(hour: 20, minute: 0)
        )
        let tenAM = makeDate(hour: 10, minute: 0)
        XCTAssertTrue(rule.isActive(at: tenAM))
    }

    func test_outsideTimeWindow_notActive() {
        // Window 08:00 – 20:00; test at 22:00
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["HI"],
            reply: "Hello!", enabled: true,
            startTime: timeComponents(hour: 8, minute: 0),
            endTime: timeComponents(hour: 20, minute: 0)
        )
        let tenPM = makeDate(hour: 22, minute: 0)
        XCTAssertFalse(rule.isActive(at: tenPM))
    }

    // MARK: - validation

    func test_validRule_noErrors() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["HELP"],
            reply: "Call us at 555-1234.", enabled: true
        )
        XCTAssertTrue(rule.validationErrors.isEmpty)
    }

    func test_emptyReply_producesError() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["HELP"],
            reply: "", enabled: true
        )
        XCTAssertFalse(rule.validationErrors.isEmpty)
    }

    func test_emptyTriggers_producesError() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: [],
            reply: "OK", enabled: true
        )
        XCTAssertFalse(rule.validationErrors.isEmpty)
    }

    func test_startAfterEnd_producesError() {
        let rule = AutoResponderRule(
            id: UUID(), triggers: ["HI"],
            reply: "Hello!", enabled: true,
            startTime: timeComponents(hour: 20, minute: 0),
            endTime: timeComponents(hour: 8, minute: 0)
        )
        XCTAssertFalse(rule.validationErrors.isEmpty)
    }

    // MARK: - Helpers

    private func timeComponents(hour: Int, minute: Int) -> DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }
}
