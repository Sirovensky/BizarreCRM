import XCTest
@testable import Notifications

final class NotificationDigestSchedulerTests: XCTestCase {

    private let scheduler = NotificationDigestScheduler()

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // Fixed reference: 2024-03-15 10:00:00 UTC (already past 9am)
    private var morningPast: Date {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 3; comps.day = 15
        comps.hour = 10; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    // Fixed reference: 2024-03-15 07:00:00 UTC (before 9am)
    private var morningEarly: Date {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 3; comps.day = 15
        comps.hour = 7; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    // MARK: - nextFireDate: future-only

    func test_nextFireDate_alwaysInFuture_whenTimeAlreadyPassed() {
        let policy = DigestPolicy(sendTime: DigestTime(hour: 9, minute: 0))
        let fire = scheduler.nextFireDate(from: morningPast, policy: policy, calendar: utcCalendar)
        XCTAssertGreaterThan(fire, morningPast, "nextFireDate must be strictly in the future")
    }

    func test_nextFireDate_sameDay_whenTimeNotYetReached() {
        let policy = DigestPolicy(sendTime: DigestTime(hour: 9, minute: 0))
        let fire = scheduler.nextFireDate(from: morningEarly, policy: policy, calendar: utcCalendar)
        // 7am → 9am same day
        let dayDiff = utcCalendar.dateComponents([.day], from: morningEarly, to: fire).day ?? -1
        XCTAssertEqual(dayDiff, 0)
    }

    func test_nextFireDate_nextDay_whenTimeAlreadyPassed() {
        let policy = DigestPolicy(sendTime: DigestTime(hour: 9, minute: 0))
        let fire = scheduler.nextFireDate(from: morningPast, policy: policy, calendar: utcCalendar)
        // 10am → next day 9am = 23h delta
        let hourDiff = utcCalendar.dateComponents([.hour], from: morningPast, to: fire).hour ?? -1
        XCTAssertEqual(hourDiff, 23)
    }

    func test_nextFireDate_correctHourAndMinute() {
        let policy = DigestPolicy(sendTime: DigestTime(hour: 14, minute: 30))
        let now = morningEarly // 7am
        let fire = scheduler.nextFireDate(from: now, policy: policy, calendar: utcCalendar)
        let comps = utcCalendar.dateComponents([.hour, .minute], from: fire)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }

    func test_nextFireDate_exactlyNow_schedulesNextDay() {
        // If fire time == now exactly, should push to tomorrow
        var comps = DateComponents()
        comps.year = 2024; comps.month = 3; comps.day = 15
        comps.hour = 9; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        let exactNow = utcCalendar.date(from: comps)!

        let policy = DigestPolicy(sendTime: DigestTime(hour: 9, minute: 0))
        let fire = scheduler.nextFireDate(from: exactNow, policy: policy, calendar: utcCalendar)
        XCTAssertGreaterThan(fire, exactNow)
    }

    // MARK: - DigestTime

    func test_digestTime_clampsHour() {
        let t = DigestTime(hour: 25, minute: 0)
        XCTAssertEqual(t.hour, 23)
    }

    func test_digestTime_clampsMinute() {
        let t = DigestTime(hour: 9, minute: 99)
        XCTAssertEqual(t.minute, 59)
    }

    func test_digestTime_displayString_morning() {
        let t = DigestTime(hour: 9, minute: 0)
        XCTAssertTrue(t.displayString.contains("AM") || t.displayString.contains("9"))
    }

    func test_digestTime_displayString_afternoon() {
        let t = DigestTime(hour: 14, minute: 30)
        XCTAssertTrue(t.displayString.contains("PM") || t.displayString.contains("2"))
    }

    func test_digestTime_default_is9am() {
        XCTAssertEqual(DigestTime.defaultMorning.hour, 9)
        XCTAssertEqual(DigestTime.defaultMorning.minute, 0)
    }

    // MARK: - DigestPolicy

    func test_digestPolicy_defaultIncludesAllCategories() {
        let policy = DigestPolicy()
        XCTAssertEqual(policy.includedCategories, Set(EventCategory.allCases))
    }

    func test_digestPolicy_excludingCategory_removesIt() {
        let policy = DigestPolicy().excludingCategory(.admin)
        XCTAssertFalse(policy.includedCategories.contains(.admin))
    }

    func test_digestPolicy_includingCategory_addsIt() {
        let policy = DigestPolicy(includedCategories: []).includingCategory(.billing)
        XCTAssertTrue(policy.includedCategories.contains(.billing))
    }

    func test_digestPolicy_withSendTime_updatesTime() {
        let policy = DigestPolicy().withSendTime(DigestTime(hour: 18, minute: 0))
        XCTAssertEqual(policy.sendTime.hour, 18)
    }

    func test_digestPolicy_withEnabled_toggles() {
        let p = DigestPolicy(isEnabled: true).withEnabled(false)
        XCTAssertFalse(p.isEnabled)
    }

    func test_digestPolicy_immutable_excludeDoesNotMutateOriginal() {
        let original = DigestPolicy()
        let modified = original.excludingCategory(.tickets)
        XCTAssertTrue(original.includedCategories.contains(.tickets))
        XCTAssertFalse(modified.includedCategories.contains(.tickets))
    }

    // MARK: - Scheduler enabled/disabled

    func test_nextFireDate_differentTimes_areOrdered() {
        let policy1 = DigestPolicy(sendTime: DigestTime(hour: 8, minute: 0))
        let policy2 = DigestPolicy(sendTime: DigestTime(hour: 20, minute: 0))
        let fire1 = scheduler.nextFireDate(from: morningEarly, policy: policy1, calendar: utcCalendar)
        let fire2 = scheduler.nextFireDate(from: morningEarly, policy: policy2, calendar: utcCalendar)
        XCTAssertLessThan(fire1, fire2)
    }
}
