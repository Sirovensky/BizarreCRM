import XCTest
@testable import Setup

final class SetupPayloadTests: XCTestCase {

    // MARK: - Initial state

    func testDefaultPayload_hasDefaultPaymentMethod_cash() {
        let payload = SetupPayload()
        XCTAssertTrue(payload.paymentMethods.contains(.cash))
    }

    func testDefaultPayload_hasSevenBusinessDays() {
        let payload = SetupPayload()
        XCTAssertEqual(payload.hours.count, 7)
    }

    func testDefaultPayload_weekdaysAreOpen() {
        let payload = SetupPayload()
        let weekdays = payload.hours.filter { $0.id <= 5 }
        XCTAssertTrue(weekdays.allSatisfy { $0.isOpen })
    }

    func testDefaultPayload_weekendIsClosed() {
        let payload = SetupPayload()
        let weekend = payload.hours.filter { $0.id >= 6 }
        XCTAssertTrue(weekend.allSatisfy { !$0.isOpen })
    }

    func testDefaultPayload_timezoneIsNil() {
        let payload = SetupPayload()
        XCTAssertNil(payload.timezone)
    }

    func testDefaultPayload_currencyIsNil() {
        let payload = SetupPayload()
        XCTAssertNil(payload.currency)
    }

    func testDefaultPayload_localeIsNil() {
        let payload = SetupPayload()
        XCTAssertNil(payload.locale)
    }

    func testDefaultPayload_taxRateIsNil() {
        let payload = SetupPayload()
        XCTAssertNil(payload.taxRate)
    }

    func testDefaultPayload_firstLocationIsNil() {
        let payload = SetupPayload()
        XCTAssertNil(payload.firstLocation)
    }

    // MARK: - Timezone/Locale serialisation

    func testTimezoneLocalePayload_allSet_encodes() {
        var payload = SetupPayload()
        payload.timezone = "America/New_York"
        payload.currency = "USD"
        payload.locale   = "en_US"
        let encoded = payload.timezoneLocalePayload()
        XCTAssertEqual(encoded["timezone"], "America/New_York")
        XCTAssertEqual(encoded["currency"], "USD")
        XCTAssertEqual(encoded["locale"],   "en_US")
    }

    func testTimezoneLocalePayload_nilFields_omitted() {
        let payload = SetupPayload()
        let encoded = payload.timezoneLocalePayload()
        XCTAssertTrue(encoded.isEmpty)
    }

    // MARK: - Business hours serialisation

    func testBusinessHoursPayload_containsAllDays() {
        let payload = SetupPayload()
        let encoded = payload.businessHoursPayload()
        for day in 1...7 {
            XCTAssertNotNil(encoded["hours_\(day)_isOpen"], "Missing hours_\(day)_isOpen")
        }
    }

    func testBusinessHoursPayload_mondayOpen_encodedAs1() {
        let payload = SetupPayload()
        XCTAssertEqual(payload.businessHoursPayload()["hours_1_isOpen"], "1")
    }

    func testBusinessHoursPayload_saturdayClosed_encodedAs0() {
        let payload = SetupPayload()
        XCTAssertEqual(payload.businessHoursPayload()["hours_6_isOpen"], "0")
    }

    // MARK: - Tax rate serialisation

    func testTaxRatePayload_whenSet_encodes() {
        var payload = SetupPayload()
        payload.taxRate = TaxRate(name: "GST", ratePct: 5.0, applyTo: .allItems)
        let encoded = payload.taxRatePayload()
        XCTAssertEqual(encoded["tax_name"],    "GST")
        XCTAssertEqual(encoded["tax_rate"],    "5.00")
        XCTAssertEqual(encoded["tax_apply_to"], "all")
    }

    func testTaxRatePayload_whenNil_isEmpty() {
        let payload = SetupPayload()
        XCTAssertTrue(payload.taxRatePayload().isEmpty)
    }

    func testTaxApply_taxableOnly_rawValue() {
        XCTAssertEqual(TaxApply.taxableOnly.rawValue, "taxable")
    }

    // MARK: - Payment methods serialisation

    func testPaymentMethodsPayload_singleMethod_encodes() {
        var payload = SetupPayload()
        payload.paymentMethods = [.cash]
        let encoded = payload.paymentMethodsPayload()
        XCTAssertEqual(encoded["payment_methods"], "cash")
    }

    func testPaymentMethodsPayload_multipleMethods_sortedJoined() {
        var payload = SetupPayload()
        payload.paymentMethods = [.card, .cash]
        let encoded = payload.paymentMethodsPayload()
        // sorted alphabetically: card,cash
        XCTAssertEqual(encoded["payment_methods"], "card,cash")
    }

    // MARK: - First location serialisation

    func testFirstLocationPayload_whenSet_encodes() {
        var payload = SetupPayload()
        payload.firstLocation = SetupLocation(name: "Main", address: "123 St", phone: "555-1234")
        let encoded = payload.firstLocationPayload()
        XCTAssertEqual(encoded["location_name"],    "Main")
        XCTAssertEqual(encoded["location_address"], "123 St")
        XCTAssertEqual(encoded["location_phone"],   "555-1234")
    }

    func testFirstLocationPayload_emptyPhone_omitsKey() {
        var payload = SetupPayload()
        payload.firstLocation = SetupLocation(name: "HQ", address: "1 Main St", phone: "")
        let encoded = payload.firstLocationPayload()
        XCTAssertNil(encoded["location_phone"])
    }

    func testFirstLocationPayload_whenNil_isEmpty() {
        let payload = SetupPayload()
        XCTAssertTrue(payload.firstLocationPayload().isEmpty)
    }

    // MARK: - BusinessDay helpers

    func testBusinessDay_weekdayNames_areCorrect() {
        let day1 = BusinessDay(weekday: 1, isOpen: true, openAt: .init(), closeAt: .init())
        XCTAssertEqual(day1.weekdayName, "Monday")
        let day7 = BusinessDay(weekday: 7, isOpen: true, openAt: .init(), closeAt: .init())
        XCTAssertEqual(day7.weekdayName, "Sunday")
    }

    func testBusinessDay_invalidWeekday_showsFallback() {
        let dayX = BusinessDay(weekday: 99, isOpen: true, openAt: .init(), closeAt: .init())
        XCTAssertTrue(dayX.weekdayName.hasPrefix("Day"))
    }

    func testBusinessDay_defaults_idIsWeekday() {
        let days = BusinessDay.defaults
        for (index, day) in days.enumerated() {
            XCTAssertEqual(day.id, index + 1)
        }
    }

    // MARK: - SetupLocation equality

    func testSetupLocation_equality() {
        let a = SetupLocation(name: "A", address: "1 St", phone: "123")
        let b = SetupLocation(name: "A", address: "1 St", phone: "123")
        XCTAssertEqual(a, b)
    }

    func testSetupLocation_inequality_whenNameDiffers() {
        let a = SetupLocation(name: "A", address: "1 St", phone: "")
        let b = SetupLocation(name: "B", address: "1 St", phone: "")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - TaxRate equality

    func testTaxRate_equality() {
        let a = TaxRate(name: "Tax", ratePct: 8.0, applyTo: .allItems)
        let b = TaxRate(name: "Tax", ratePct: 8.0, applyTo: .allItems)
        XCTAssertEqual(a, b)
    }
}
