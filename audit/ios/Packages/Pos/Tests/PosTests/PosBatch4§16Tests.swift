#if canImport(UIKit)
import XCTest
@testable import Pos

// MARK: - PosBatch4§16Tests
//
// §16 b4 — Tests for the additions landed in 225ac055:
//   1. TenderMethod.financing case (apiValue, systemImage, isReady, requiresDetailsSheet)
//   2. TenderMethod.check systemImage = "checkmark.rectangle.fill"
//   3. AppliedTender.Kind.systemImage for all three cases
//   4. AppliedTender.Kind.accessibilityLabel for all three cases
//   5. AppliedTender.Kind.loyaltyRedemption existence and icon
//   6. ReceiptPrinterConnectionStatus label / systemImage / accessibilityLabel
//   7. ReceiptPrinterStatusViewModel provider-based checkPrinter
//   8. TipPresetConfigViewModel duplicate-percentage validation

final class PosBatch4§16Tests: XCTestCase {

    // MARK: - 1. TenderMethod.financing

    func test_financing_apiValue() {
        XCTAssertEqual(TenderMethod.financing.apiValue, "financing")
    }

    func test_financing_isReady() {
        // Partner link has no SDK dependency — flagged ready.
        XCTAssertTrue(TenderMethod.financing.isReady)
    }

    func test_financing_requiresDetailsSheet() {
        // Financing opens PosFinancingLinkSheet.
        XCTAssertTrue(TenderMethod.financing.requiresDetailsSheet)
    }

    func test_financing_displayName_nonEmpty() {
        XCTAssertFalse(TenderMethod.financing.displayName.isEmpty)
    }

    func test_financing_tileSubtitle_containsPartnerNames() {
        let subtitle = TenderMethod.financing.tileSubtitle
        XCTAssertTrue(
            subtitle.contains("Affirm") || subtitle.contains("Klarna"),
            "Expected partner names in subtitle, got: \(subtitle)"
        )
    }

    // MARK: - 2. TenderMethod.check systemImage

    func test_check_systemImage() {
        XCTAssertEqual(TenderMethod.check.systemImage, "checkmark.rectangle.fill")
    }

    func test_check_apiValue() {
        XCTAssertEqual(TenderMethod.check.apiValue, "check")
    }

    // MARK: - 3 & 4. AppliedTender.Kind.systemImage + accessibilityLabel

    func test_appliedTender_giftCard_systemImage() {
        XCTAssertEqual(AppliedTender.Kind.giftCard.systemImage, "giftcard.fill")
    }

    func test_appliedTender_storeCredit_systemImage() {
        XCTAssertEqual(AppliedTender.Kind.storeCredit.systemImage, "dollarsign.circle.fill")
    }

    func test_appliedTender_loyaltyRedemption_systemImage() {
        XCTAssertEqual(AppliedTender.Kind.loyaltyRedemption.systemImage, "star.circle.fill")
    }

    func test_appliedTender_giftCard_accessibilityLabel() {
        XCTAssertEqual(AppliedTender.Kind.giftCard.accessibilityLabel, "Gift card")
    }

    func test_appliedTender_storeCredit_accessibilityLabel() {
        XCTAssertEqual(AppliedTender.Kind.storeCredit.accessibilityLabel, "Store credit")
    }

    func test_appliedTender_loyaltyRedemption_accessibilityLabel() {
        XCTAssertEqual(AppliedTender.Kind.loyaltyRedemption.accessibilityLabel, "Loyalty points")
    }

    // MARK: - 5. AppliedTender.Kind.loyaltyRedemption construction

    func test_appliedTender_loyaltyRedemption_init() {
        let tender = AppliedTender(
            kind: .loyaltyRedemption,
            amountCents: 500,
            label: "500 pts"
        )
        XCTAssertEqual(tender.kind, .loyaltyRedemption)
        XCTAssertEqual(tender.amountCents, 500)
    }

    func test_appliedTender_clampNegativeAmount() {
        let tender = AppliedTender(kind: .loyaltyRedemption, amountCents: -100, label: "pts")
        XCTAssertEqual(tender.amountCents, 0)
    }

    // MARK: - 6. ReceiptPrinterConnectionStatus

    func test_printerStatus_connected_label() {
        XCTAssertEqual(ReceiptPrinterConnectionStatus.connected.label, "Printer ready")
    }

    func test_printerStatus_notPaired_label() {
        XCTAssertEqual(ReceiptPrinterConnectionStatus.notPaired.label, "No printer")
    }

    func test_printerStatus_offline_label() {
        XCTAssertEqual(ReceiptPrinterConnectionStatus.offline(reason: "BT off").label, "Printer offline")
    }

    func test_printerStatus_connected_systemImage() {
        XCTAssertEqual(ReceiptPrinterConnectionStatus.connected.systemImage, "printer.fill")
    }

    func test_printerStatus_offline_accessibilityLabel_includesReason() {
        let status = ReceiptPrinterConnectionStatus.offline(reason: "No route to host")
        XCTAssertTrue(
            status.accessibilityLabel.contains("No route to host"),
            "Expected reason in a11y label, got: \(status.accessibilityLabel)"
        )
    }

    func test_printerStatus_notPaired_accessibilityLabel() {
        XCTAssertEqual(
            ReceiptPrinterConnectionStatus.notPaired.accessibilityLabel,
            "Receipt printer not paired"
        )
    }

    // MARK: - 7. ReceiptPrinterStatusViewModel (provider injection)

    @MainActor
    func test_viewModel_checkPrinter_connected() async {
        let vm = ReceiptPrinterStatusViewModel(printerProvider: { true })
        await vm.checkPrinter()
        XCTAssertEqual(vm.status, .connected)
    }

    @MainActor
    func test_viewModel_checkPrinter_offline_whenProviderReturnsFalse() async {
        let vm = ReceiptPrinterStatusViewModel(printerProvider: { false })
        await vm.checkPrinter()
        if case .offline = vm.status {
            // Expected — printer not responding
        } else {
            XCTFail("Expected .offline, got \(vm.status)")
        }
    }

    @MainActor
    func test_viewModel_initialStatus_isNotPaired() {
        let vm = ReceiptPrinterStatusViewModel(printerProvider: { true })
        // Default before any poll is .notPaired
        XCTAssertEqual(vm.status, .notPaired)
    }

    // MARK: - 8. TipPresetConfigViewModel duplicate-percentage validation

    @MainActor
    func test_tipConfig_noDuplicates_noError() async {
        let store = TipPresetStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        let vm = TipPresetConfigViewModel(store: store)
        await vm.load()
        // Defaults are 15/18/20/25 — all unique, no validation error.
        XCTAssertNil(vm.validationError)
    }

    @MainActor
    func test_tipConfig_duplicatePercent_setsValidationError() async {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = TipPresetStore(defaults: defaults)
        let vm = TipPresetConfigViewModel(store: store)
        await vm.load()

        // Set index 0 to 20% — same as index 2 in the default row.
        vm.setPercentage(20, at: 0)
        XCTAssertNotNil(vm.validationError, "Expected duplicate-percent error")
    }

    @MainActor
    func test_tipConfig_removingDuplicate_clearsError() async {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = TipPresetStore(defaults: defaults)
        let vm = TipPresetConfigViewModel(store: store)
        await vm.load()

        // Create a duplicate first.
        vm.setPercentage(20, at: 0)
        XCTAssertNotNil(vm.validationError)

        // Remove the duplicate row.
        vm.removePreset(at: IndexSet(integer: 0))
        XCTAssertNil(vm.validationError, "Error should clear after removing duplicate")
    }

    @MainActor
    func test_tipConfig_save_blockedOnValidationError() async {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = TipPresetStore(defaults: defaults)
        let vm = TipPresetConfigViewModel(store: store)
        await vm.load()

        vm.setPercentage(20, at: 0)          // duplicate → error
        await vm.save()                       // should no-op
        // After the no-op save, error is still set.
        XCTAssertNotNil(vm.validationError)
    }
}

#endif
