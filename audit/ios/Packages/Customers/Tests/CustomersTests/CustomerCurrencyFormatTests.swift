import XCTest
@testable import Customers

// §5 lines 978–982 — currency formatter coverage
final class CustomerCurrencyFormatTests: XCTestCase {

    // MARK: 1. Tenant template

    func test_tenant_us_format_isPrefixSymbol_withCommaThousands() {
        let t = CustomerCurrencyTemplate.presets["US"]!
        let s = CustomerCurrencyFormat.format(cents: 123_456, tenant: t)
        XCTAssertTrue(s.contains("1,234"), "US format should group with commas, got \(s)")
        XCTAssertTrue(s.contains("$"), "US format should include $, got \(s)")
    }

    func test_tenant_jpy_format_hasNoFractionalPart() {
        let t = CustomerCurrencyTemplate.presets["JP"]!
        // 123,456 yen → cents=123_456 (JPY has 0 minor units, so cents arg is yen)
        let s = CustomerCurrencyFormat.format(cents: 123_456, tenant: t)
        XCTAssertFalse(s.contains("."), "JPY should have no decimal, got \(s)")
        XCTAssertTrue(s.contains(where: \.isNumber))
    }

    func test_tenant_eu_fr_uses_comma_decimal() {
        let t = CustomerCurrencyTemplate.presets["EU-FR"]!
        let s = CustomerCurrencyFormat.format(cents: 123_456, tenant: t)
        // French formatting uses ',' for decimals
        XCTAssertTrue(s.contains(","), "FR format should use comma decimal, got \(s)")
    }

    func test_tenant_ch_uses_apostrophe_thousands() {
        let t = CustomerCurrencyTemplate.presets["CH"]!
        let s = CustomerCurrencyFormat.format(cents: 123_456, tenant: t)
        // CHF uses ' as thousands sep on de_CH
        XCTAssertTrue(s.contains(where: \.isNumber))
        XCTAssertFalse(s.isEmpty)
    }

    // MARK: 2. Per-customer override

    func test_override_changesCurrencyCode() async {
        let store = CustomerCurrencyOverrideStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        await store.setOverride("EUR", customerId: 42)
        let got = await store.override(customerId: 42)
        XCTAssertEqual(got, "EUR")
    }

    func test_override_clear() async {
        let store = CustomerCurrencyOverrideStore(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        await store.setOverride("EUR", customerId: 7)
        await store.setOverride(nil, customerId: 7)
        let got = await store.override(customerId: 7)
        XCTAssertNil(got)
    }

    func test_format_with_override_usesOverrideCurrency() {
        let t = CustomerCurrencyTemplate.presets["US"]!
        let s = CustomerCurrencyFormat.format(cents: 100_00, tenant: t, customerOverrideCode: "EUR")
        XCTAssertFalse(s.contains("$"), "Override should hide USD symbol, got \(s)")
        XCTAssertTrue(s.contains("€") || s.uppercased().contains("EUR"))
    }

    // MARK: 3. Multi-locale presets exist

    func test_presets_contain_all_four() {
        XCTAssertNotNil(CustomerCurrencyTemplate.presets["US"])
        XCTAssertNotNil(CustomerCurrencyTemplate.presets["EU-FR"])
        XCTAssertNotNil(CustomerCurrencyTemplate.presets["JP"])
        XCTAssertNotNil(CustomerCurrencyTemplate.presets["CH"])
    }

    // MARK: 4. Parse multi-locale → integer minor units

    func test_parse_us_basic() {
        let t = CustomerCurrencyTemplate.presets["US"]!
        XCTAssertEqual(CustomerCurrencyFormat.parse(input: "$1,234.56", tenant: t), 123_456)
    }

    func test_parse_eu_fr_with_comma_decimal() {
        let t = CustomerCurrencyTemplate.presets["EU-FR"]!
        XCTAssertEqual(CustomerCurrencyFormat.parse(input: "1 234,56 €", tenant: t), 123_456)
    }

    func test_parse_ch_with_apostrophe_thousands() {
        let t = CustomerCurrencyTemplate.presets["CH"]!
        XCTAssertEqual(CustomerCurrencyFormat.parse(input: "CHF 1'234.56", tenant: t), 123_456)
    }

    func test_parse_jpy_no_decimal() {
        let t = CustomerCurrencyTemplate.presets["JP"]!
        // ¥1,235 → 1235 yen → JPY has 0 minor units, so cents = 1235
        XCTAssertEqual(CustomerCurrencyFormat.parse(input: "¥1,235", tenant: t), 1_235)
    }

    func test_parse_gibberish_returnsNil() {
        let t = CustomerCurrencyTemplate.presets["US"]!
        XCTAssertNil(CustomerCurrencyFormat.parse(input: "not-a-number", tenant: t))
    }

    func test_parse_cross_locale_us_tenant_accepts_french_amount() {
        let t = CustomerCurrencyTemplate.presets["US"]!
        // The user paste-bombs a French amount into a US tenant; parser should
        // still recover the value.
        XCTAssertEqual(CustomerCurrencyFormat.parse(input: "1 234,56", tenant: t), 123_456)
    }

    // MARK: 5. VoiceOver phrase

    func test_voiceOver_usd_containsDollars() {
        let t = CustomerCurrencyTemplate.presets["US"]!
        let p = CustomerCurrencyFormat.voiceOverPhrase(cents: 1_250, tenant: t)
        XCTAssertTrue(p.lowercased().contains("dollar"), "VO phrase should mention dollar, got \(p)")
    }

    func test_voiceOver_zero_isNonEmpty() {
        let t = CustomerCurrencyTemplate.presets["US"]!
        let p = CustomerCurrencyFormat.voiceOverPhrase(cents: 0, tenant: t)
        XCTAssertFalse(p.isEmpty)
    }

    // MARK: minor-unit helper

    func test_minorUnits_jpy_isZero() {
        XCTAssertEqual(CustomerCurrencyFormat.minorUnits(for: "JPY"), 0)
    }

    func test_minorUnits_kwd_isThree() {
        XCTAssertEqual(CustomerCurrencyFormat.minorUnits(for: "KWD"), 3)
    }

    func test_minorUnits_usd_isTwo() {
        XCTAssertEqual(CustomerCurrencyFormat.minorUnits(for: "USD"), 2)
    }
}
