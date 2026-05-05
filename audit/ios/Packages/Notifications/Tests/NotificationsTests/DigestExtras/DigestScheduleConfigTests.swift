import XCTest
@testable import Notifications

final class DigestScheduleConfigTests: XCTestCase {

    // MARK: - DigestCadence

    func test_cadence_off_isNotActive() {
        XCTAssertFalse(DigestCadence.off.isActive)
    }

    func test_cadence_hourly_isActive() {
        XCTAssertTrue(DigestCadence.hourly.isActive)
    }

    func test_cadence_daily_isActive() {
        XCTAssertTrue(DigestCadence.daily.isActive)
    }

    func test_cadence_threeDaily_isActive() {
        XCTAssertTrue(DigestCadence.threeDaily.isActive)
    }

    func test_cadence_off_fireHours_isEmpty() {
        XCTAssertTrue(DigestCadence.off.fireHours.isEmpty)
    }

    func test_cadence_daily_fireHours_single9() {
        XCTAssertEqual(DigestCadence.daily.fireHours, [9])
    }

    func test_cadence_threeDaily_fireHours_count() {
        XCTAssertEqual(DigestCadence.threeDaily.fireHours.count, 3)
    }

    func test_cadence_hourly_fireHours_count() {
        XCTAssertEqual(DigestCadence.hourly.fireHours.count, 24)
    }

    func test_cadence_allCases_hasExpectedCount() {
        XCTAssertEqual(DigestCadence.allCases.count, 4)
    }

    func test_cadence_rawValues_stable() {
        XCTAssertEqual(DigestCadence.off.rawValue, "off")
        XCTAssertEqual(DigestCadence.threeDaily.rawValue, "3x_daily")
    }

    // MARK: - QuietHoursConfig

    func test_quietHours_normalWindow_suppressesMiddle() {
        let config = QuietHoursConfig(startHour: 9, endHour: 17)
        XCTAssertTrue(config.isSuppressed(hour: 12))
        XCTAssertTrue(config.isSuppressed(hour: 9))
        XCTAssertTrue(config.isSuppressed(hour: 17))
    }

    func test_quietHours_normalWindow_doesNotSuppressOutside() {
        let config = QuietHoursConfig(startHour: 9, endHour: 17)
        XCTAssertFalse(config.isSuppressed(hour: 8))
        XCTAssertFalse(config.isSuppressed(hour: 18))
    }

    func test_quietHours_wrapMidnightWindow_suppressesNight() {
        // 22–06 wraps midnight
        let config = QuietHoursConfig(startHour: 22, endHour: 6)
        XCTAssertTrue(config.isSuppressed(hour: 23))
        XCTAssertTrue(config.isSuppressed(hour: 0))
        XCTAssertTrue(config.isSuppressed(hour: 3))
        XCTAssertTrue(config.isSuppressed(hour: 6))
    }

    func test_quietHours_wrapMidnightWindow_doesNotSuppressDay() {
        let config = QuietHoursConfig(startHour: 22, endHour: 6)
        XCTAssertFalse(config.isSuppressed(hour: 7))
        XCTAssertFalse(config.isSuppressed(hour: 12))
        XCTAssertFalse(config.isSuppressed(hour: 21))
    }

    func test_quietHours_disabled_neverSuppresses() {
        let config = QuietHoursConfig(startHour: 0, endHour: 23, isEnabled: false)
        for h in 0..<24 {
            XCTAssertFalse(config.isSuppressed(hour: h), "Hour \(h) should not be suppressed when disabled")
        }
    }

    func test_quietHours_defaultNight_startAndEnd() {
        XCTAssertEqual(QuietHoursConfig.defaultNight.startHour, 22)
        XCTAssertEqual(QuietHoursConfig.defaultNight.endHour, 7)
    }

    func test_quietHours_clampsStartHour() {
        let config = QuietHoursConfig(startHour: 30, endHour: 5)
        XCTAssertEqual(config.startHour, 23)
    }

    func test_quietHours_clampsEndHour() {
        let config = QuietHoursConfig(startHour: 22, endHour: -1)
        XCTAssertEqual(config.endHour, 0)
    }

    func test_quietHours_withStartHour_updatesStart() {
        let updated = QuietHoursConfig.defaultNight.withStartHour(20)
        XCTAssertEqual(updated.startHour, 20)
        XCTAssertEqual(updated.endHour, QuietHoursConfig.defaultNight.endHour)
    }

    func test_quietHours_withEndHour_updatesEnd() {
        let updated = QuietHoursConfig.defaultNight.withEndHour(8)
        XCTAssertEqual(updated.endHour, 8)
        XCTAssertEqual(updated.startHour, QuietHoursConfig.defaultNight.startHour)
    }

    func test_quietHours_withEnabled_toggles() {
        let disabled = QuietHoursConfig.defaultNight.withEnabled(false)
        XCTAssertFalse(disabled.isEnabled)
        let reenabled = disabled.withEnabled(true)
        XCTAssertTrue(reenabled.isEnabled)
    }

    func test_quietHours_displayString_containsHours() {
        let config = QuietHoursConfig(startHour: 22, endHour: 7)
        let s = config.displayString
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.contains("AM") || s.contains("PM"))
    }

    func test_quietHours_immutable_originalUnchanged() {
        let original = QuietHoursConfig.defaultNight
        let _ = original.withStartHour(20)
        XCTAssertEqual(original.startHour, 22, "Original should be unchanged after copy-on-write")
    }

    // MARK: - DigestScheduleConfig

    func test_scheduleConfig_defaultCadence_isDaily() {
        XCTAssertEqual(DigestScheduleConfig().cadence, .daily)
    }

    func test_scheduleConfig_withCadence_returnsNewCopy() {
        let config = DigestScheduleConfig().withCadence(.hourly)
        XCTAssertEqual(config.cadence, .hourly)
    }

    func test_scheduleConfig_withCadence_doesNotMutateOriginal() {
        let original = DigestScheduleConfig()
        let _ = original.withCadence(.off)
        XCTAssertEqual(original.cadence, .daily)
    }

    func test_scheduleConfig_withQuietHours_updatesQuietHours() {
        let newQH = QuietHoursConfig(startHour: 20, endHour: 6)
        let config = DigestScheduleConfig().withQuietHours(newQH)
        XCTAssertEqual(config.quietHours.startHour, 20)
    }

    func test_scheduleConfig_effectiveFireHours_removesQuietHours() {
        // Daily at 9am, quiet from 8–10 → 9 is suppressed
        let qh = QuietHoursConfig(startHour: 8, endHour: 10, isEnabled: true)
        let config = DigestScheduleConfig(cadence: .daily, quietHours: qh)
        XCTAssertTrue(config.effectiveFireHours.isEmpty, "Hour 9 should be suppressed")
    }

    func test_scheduleConfig_effectiveFireHours_quietDisabled_allPreserved() {
        let qh = QuietHoursConfig(startHour: 0, endHour: 23, isEnabled: false)
        let config = DigestScheduleConfig(cadence: .daily, quietHours: qh)
        XCTAssertEqual(config.effectiveFireHours, [9])
    }

    func test_scheduleConfig_nextFireHour_afterCurrentHour() {
        // threeDaily fires at 8, 13, 18; current=10 → next=13
        let config = DigestScheduleConfig(
            cadence: .threeDaily,
            quietHours: QuietHoursConfig(startHour: 22, endHour: 5)
        )
        XCTAssertEqual(config.nextFireHour(after: 10), 13)
    }

    func test_scheduleConfig_nextFireHour_wrapsToFirstHour() {
        // threeDaily fires at 8, 13, 18; current=20 → wraps to 8
        let config = DigestScheduleConfig(
            cadence: .threeDaily,
            quietHours: QuietHoursConfig(startHour: 22, endHour: 5)
        )
        XCTAssertEqual(config.nextFireHour(after: 20), 8)
    }

    func test_scheduleConfig_nextFireHour_offCadence_returnsNil() {
        let config = DigestScheduleConfig(cadence: .off)
        XCTAssertNil(config.nextFireHour(after: 9))
    }

    func test_scheduleConfig_nextFireHour_allSuppressed_returnsNil() {
        // daily at 9, suppress all hours
        let qh = QuietHoursConfig(startHour: 0, endHour: 23, isEnabled: true)
        let config = DigestScheduleConfig(cadence: .daily, quietHours: qh)
        XCTAssertNil(config.nextFireHour(after: 5))
    }

    // MARK: - Codable round-trip

    func test_digestCadence_codable_roundTrip() throws {
        let cadence = DigestCadence.threeDaily
        let data    = try JSONEncoder().encode(cadence)
        let decoded = try JSONDecoder().decode(DigestCadence.self, from: data)
        XCTAssertEqual(decoded, cadence)
    }

    func test_digestScheduleConfig_codable_roundTrip() throws {
        let config  = DigestScheduleConfig(cadence: .hourly)
        let data    = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(DigestScheduleConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }
}
