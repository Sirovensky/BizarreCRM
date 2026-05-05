import XCTest
@testable import Notifications

final class SnoozeDurationPickerViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 0) // 2001-01-01 00:00:00 UTC
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // MARK: - SnoozeDuration fire dates

    func test_minutes_fireDate_addsMinutes() {
        let d: SnoozeDuration = .minutes(15)
        let fire = d.fireDate(from: now, calendar: calendar)
        XCTAssertEqual(fire.timeIntervalSince(now), 15 * 60, accuracy: 1)
    }

    func test_oneHour_fireDate_addsOneHour() {
        let d: SnoozeDuration = .oneHour
        XCTAssertEqual(d.fireDate(from: now, calendar: calendar).timeIntervalSince(now), 3600, accuracy: 1)
    }

    func test_tomorrowMorning_fireDate_isTomorrow9am() {
        let d: SnoozeDuration = .tomorrowMorning
        let fire = d.fireDate(from: now, calendar: calendar)
        let comps = calendar.dateComponents([.hour, .day], from: now, to: fire)
        XCTAssertEqual(comps.hour, 9)   // exactly 9h from midnight
        // day incremented by 1
        let dayComps = calendar.dateComponents([.day], from: now, to: fire)
        XCTAssertGreaterThanOrEqual(dayComps.day ?? 0, 1)
    }

    func test_custom_fireDate_addsCustomMinutes() {
        let d: SnoozeDuration = .custom(minutes: 45)
        XCTAssertEqual(d.fireDate(from: now, calendar: calendar).timeIntervalSince(now), 45 * 60, accuracy: 1)
    }

    // MARK: - Display names

    func test_fifteenMinutes_displayName() {
        XCTAssertEqual(SnoozeDuration.fifteenMinutes.displayName, "15 min")
    }

    func test_oneHour_displayName() {
        XCTAssertEqual(SnoozeDuration.oneHour.displayName, "1 hour")
    }

    func test_twoHours_displayName() {
        XCTAssertEqual(SnoozeDuration.minutes(120).displayName, "2 hours")
    }

    func test_tomorrowMorning_displayName_containsTomorrow() {
        XCTAssertTrue(SnoozeDuration.tomorrowMorning.displayName.contains("Tomorrow"))
    }

    func test_custom_displayName_containsCustom() {
        XCTAssertTrue(SnoozeDuration.custom(minutes: 25).displayName.contains("custom"))
    }

    // MARK: - Equatable

    func test_snoozeDuration_equatable_minutesMatch() {
        XCTAssertEqual(SnoozeDuration.minutes(15), SnoozeDuration.minutes(15))
    }

    func test_snoozeDuration_equatable_minutesNotMatch() {
        XCTAssertNotEqual(SnoozeDuration.minutes(15), SnoozeDuration.minutes(30))
    }

    func test_snoozeDuration_equatable_customMatch() {
        XCTAssertEqual(SnoozeDuration.custom(minutes: 20), SnoozeDuration.custom(minutes: 20))
    }

    func test_snoozeDuration_equatable_mixedTypes_notEqual() {
        XCTAssertNotEqual(SnoozeDuration.minutes(15), SnoozeDuration.custom(minutes: 15))
    }

    func test_snoozeDuration_equatable_tomorrowAtMatch() {
        XCTAssertEqual(SnoozeDuration.tomorrowAt(hour: 9, minute: 0), SnoozeDuration.tomorrowAt(hour: 9, minute: 0))
    }

    func test_snoozeDuration_equatable_tomorrowAtNotMatch() {
        XCTAssertNotEqual(SnoozeDuration.tomorrowAt(hour: 9, minute: 0), SnoozeDuration.tomorrowAt(hour: 8, minute: 0))
    }

    // MARK: - ViewModel initial state

    @MainActor
    func test_vm_initialSelectedDuration_isFifteenMinutes() {
        let vm = SnoozeDurationPickerViewModel()
        XCTAssertEqual(vm.selectedDuration, .fifteenMinutes)
    }

    @MainActor
    func test_vm_presets_containsThreeItems() {
        let vm = SnoozeDurationPickerViewModel()
        XCTAssertEqual(vm.presets.count, 3)
    }

    @MainActor
    func test_vm_select_changesSelectedDuration() {
        let vm = SnoozeDurationPickerViewModel()
        vm.select(.oneHour)
        XCTAssertEqual(vm.selectedDuration, .oneHour)
    }

    @MainActor
    func test_vm_selectCustom_setsCustomDuration() {
        let vm = SnoozeDurationPickerViewModel()
        vm.customMinutes = 45
        vm.selectCustom()
        XCTAssertEqual(vm.selectedDuration, .custom(minutes: 45))
        XCTAssertTrue(vm.isCustomSelected)
    }

    @MainActor
    func test_vm_previewFireDate_futureDate() {
        let vm = SnoozeDurationPickerViewModel(initialDuration: .minutes(15))
        let fire = vm.previewFireDate(from: now, calendar: calendar)
        XCTAssertGreaterThan(fire, now)
    }

    @MainActor
    func test_vm_initialCustom_notCustomSelected() {
        let vm = SnoozeDurationPickerViewModel()
        XCTAssertFalse(vm.isCustomSelected)
    }

    @MainActor
    func test_vm_fireTimeLabel_notEmpty() {
        let vm = SnoozeDurationPickerViewModel()
        XCTAssertFalse(vm.fireTimeLabel(from: now, calendar: calendar).isEmpty)
    }
}
