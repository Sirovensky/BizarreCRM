import Testing
import Foundation
@testable import Notifications

// MARK: - MatrixQuietHoursEditorTests
//
// Pure unit tests for the quiet-hours domain logic used by MatrixQuietHoursEditor.
// UI rendering tests are not included (no XCTest host target).
// Covers the QuietHours value type used by the editor.

@Suite("MatrixQuietHoursEditor — QuietHours value type")
struct MatrixQuietHoursEditorTests {

    // MARK: - QuietHours construction

    @Test("default QuietHours initialises to 10 PM start, 7 AM end")
    func defaultInit() {
        let qh = QuietHours()
        #expect(qh.startMinutesFromMidnight == 22 * 60)
        #expect(qh.endMinutesFromMidnight == 7 * 60)
        #expect(qh.allowCriticalOverride == true)
    }

    @Test("custom QuietHours stores correct values")
    func customInit() {
        let qh = QuietHours(startMinutesFromMidnight: 23 * 60, endMinutesFromMidnight: 6 * 60, allowCriticalOverride: false)
        #expect(qh.startMinutesFromMidnight == 23 * 60)
        #expect(qh.endMinutesFromMidnight == 6 * 60)
        #expect(qh.allowCriticalOverride == false)
    }

    @Test("QuietHours is Equatable — equal instances are equal")
    func equatableEqual() {
        let a = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        let b = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        #expect(a == b)
    }

    @Test("QuietHours is Equatable — different instances are not equal")
    func equatableNotEqual() {
        let a = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        let b = QuietHours(startMinutesFromMidnight: 21 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        #expect(a != b)
    }

    @Test("QuietHours round-trips through Codable")
    func codable() throws {
        let original = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 6 * 60, allowCriticalOverride: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuietHours.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Midnight boundary

    @Test("midnight is represented as 0 minutes")
    func midnightZero() {
        let qh = QuietHours(startMinutesFromMidnight: 0, endMinutesFromMidnight: 6 * 60, allowCriticalOverride: true)
        #expect(qh.startMinutesFromMidnight == 0)
    }

    @Test("11:59 PM is represented as 23 * 60 + 59")
    func almostMidnight() {
        let minutes = 23 * 60 + 59
        let qh = QuietHours(startMinutesFromMidnight: minutes, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        #expect(qh.startMinutesFromMidnight == minutes)
    }

    // MARK: - NotificationPreference.withQuietHours integration

    @Test("withQuietHours sets quiet hours on preference")
    func withQuietHoursOnPref() {
        let pref = NotificationPreference.defaultPreference(for: .ticketAssigned)
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        let updated = pref.withQuietHours(qh)
        #expect(updated.quietHours == qh)
        #expect(pref.quietHours == nil) // original unchanged
    }

    @Test("withQuietHours(nil) clears quiet hours on preference")
    func clearQuietHoursOnPref() {
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        let pref = NotificationPreference(
            event: .ticketAssigned,
            pushEnabled: true, inAppEnabled: true, emailEnabled: false, smsEnabled: false,
            quietHours: qh
        )
        let cleared = pref.withQuietHours(nil)
        #expect(cleared.quietHours == nil)
    }

    // MARK: - MatrixRow quiet hours integration

    @Test("MatrixRow.withQuietHours does not mutate original")
    func matrixRowWithQHImmutable() {
        let row = MatrixRow(event: .ticketAssigned, pushEnabled: true, emailEnabled: false, smsEnabled: false)
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        let updated = row.withQuietHours(qh)
        #expect(row.quietHours == nil)
        #expect(updated.quietHours != nil)
    }

    @Test("MatrixRow.toPreference transfers quiet hours")
    func matrixRowToPreferenceQH() {
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: false)
        let row = MatrixRow(event: .invoicePaid, pushEnabled: true, emailEnabled: false, smsEnabled: false, quietHours: qh)
        let pref = row.toPreference()
        #expect(pref.quietHours == qh)
    }
}
