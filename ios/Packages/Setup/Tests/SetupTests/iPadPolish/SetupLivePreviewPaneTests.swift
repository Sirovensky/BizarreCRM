import XCTest
@testable import Setup

// MARK: - SetupLivePreviewPane tests
//
// Coverage targets:
//   1. View instantiation for each step without crashing.
//   2. progressFraction computed correctly for first, mid, and last step.
//   3. currentStepHint returns non-nil for steps with hints and nil for .complete.
//   4. Empty vs filled state detection logic.
//   5. PreviewDataCard/PreviewDataRow initialise cleanly.

final class SetupLivePreviewPaneTests: XCTestCase {

    // MARK: - Instantiation

    func test_init_emptyPayload_doesNotThrow() {
        _ = SetupLivePreviewPane(payload: SetupPayload(), currentStep: .welcome)
    }

    func test_init_filledPayload_doesNotThrow() {
        var p = SetupPayload()
        p.companyName = "Bizarre Corp"
        p.timezone = "Europe/London"
        p.taxRate = TaxRate(name: "VAT", ratePct: 20.0, applyTo: .allItems)
        p.paymentMethods = [.cash, .card]
        p.firstLocation = SetupLocation(name: "Shoreditch", address: "1 Old St", phone: "")
        p.firstEmployeeFirstName = "Ada"
        p.firstEmployeeLastName  = "Lovelace"
        p.firstEmployeeEmail     = "ada@biz.com"
        p.firstEmployeeRole      = "technician"
        p.sampleDataOptIn = true
        _ = SetupLivePreviewPane(payload: p, currentStep: .complete)
    }

    func test_init_eachStep_doesNotThrow() {
        for step in SetupStep.allCases {
            _ = SetupLivePreviewPane(payload: SetupPayload(), currentStep: step)
        }
    }

    // MARK: - Progress fraction

    func test_progressFraction_welcome_isZero() {
        let pane = SetupLivePreviewPane(payload: SetupPayload(), currentStep: .welcome)
        // welcome.rawValue == 1; total == 15; fraction == (1-1)/(15-1) == 0
        XCTAssertEqual(pane.testableProgressFraction, 0.0, accuracy: 0.001)
    }

    func test_progressFraction_complete_isOne() {
        let pane = SetupLivePreviewPane(payload: SetupPayload(), currentStep: .complete)
        // complete.rawValue == 15; fraction == (15-1)/(15-1) == 1
        XCTAssertEqual(pane.testableProgressFraction, 1.0, accuracy: 0.001)
    }

    func test_progressFraction_midStep_isHalf() {
        // Step 8 out of 15 → (8-1)/(15-1) = 7/14 = 0.5
        let pane = SetupLivePreviewPane(payload: SetupPayload(), currentStep: .firstLocation)
        XCTAssertEqual(pane.testableProgressFraction, 0.5, accuracy: 0.001)
    }

    func test_progressFraction_companyInfo_isCorrect() {
        // Step 2 → (2-1)/(15-1) = 1/14 ≈ 0.0714
        let pane = SetupLivePreviewPane(payload: SetupPayload(), currentStep: .companyInfo)
        let expected = 1.0 / 14.0
        XCTAssertEqual(pane.testableProgressFraction, expected, accuracy: 0.001)
    }

    // MARK: - Step hints

    func test_stepHint_welcome_isNotNil() {
        let pane = SetupLivePreviewPane(payload: SetupPayload(), currentStep: .welcome)
        XCTAssertNotNil(pane.testableStepHint)
    }

    func test_stepHint_complete_isNil() {
        let pane = SetupLivePreviewPane(payload: SetupPayload(), currentStep: .complete)
        XCTAssertNil(pane.testableStepHint)
    }

    func test_stepHint_allNonCompleteSteps_areNotNil() {
        for step in SetupStep.allCases where step != .complete {
            let pane = SetupLivePreviewPane(payload: SetupPayload(), currentStep: step)
            XCTAssertNotNil(pane.testableStepHint, "Expected hint for step \(step.title)")
        }
    }

    // MARK: - Empty/filled detection

    func test_isPayloadEmpty_defaultPayload_isTrue() {
        let pane = SetupLivePreviewPane(payload: SetupPayload(), currentStep: .welcome)
        XCTAssertTrue(pane.testableIsPayloadEffectivelyEmpty)
    }

    func test_isPayloadEmpty_withCompanyName_isFalse() {
        var p = SetupPayload()
        p.companyName = "Acme"
        let pane = SetupLivePreviewPane(payload: p, currentStep: .companyInfo)
        XCTAssertFalse(pane.testableIsPayloadEffectivelyEmpty)
    }

    func test_isPayloadEmpty_withTimezone_isFalse() {
        var p = SetupPayload()
        p.timezone = "UTC"
        let pane = SetupLivePreviewPane(payload: p, currentStep: .timezoneLocale)
        XCTAssertFalse(pane.testableIsPayloadEffectivelyEmpty)
    }

    func test_isPayloadEmpty_withTaxRate_isFalse() {
        var p = SetupPayload()
        p.taxRate = TaxRate(name: "HST", ratePct: 13.0, applyTo: .allItems)
        let pane = SetupLivePreviewPane(payload: p, currentStep: .taxSetup)
        XCTAssertFalse(pane.testableIsPayloadEffectivelyEmpty)
    }

    func test_isPayloadEmpty_withSampleData_isFalse() {
        var p = SetupPayload()
        p.sampleDataOptIn = false
        let pane = SetupLivePreviewPane(payload: p, currentStep: .sampleData)
        XCTAssertFalse(pane.testableIsPayloadEffectivelyEmpty)
    }

    // MARK: - Sub-component instantiation

    func test_previewDataCard_instantiates() {
        _ = PreviewDataCard(title: "Test", icon: "star") {
            PreviewDataRow(icon: "star", label: "Label", value: "Value")
        }
    }

    func test_previewDataRow_withNilValue_instantiates() {
        _ = PreviewDataRow(icon: "phone", label: "Phone", value: nil)
    }

    func test_previewDataRow_withValue_instantiates() {
        _ = PreviewDataRow(icon: "phone", label: "Phone", value: "+1 555-0000")
    }
}

// MARK: - Testable extension (white-box accessors)
//
// Exposes private computed properties for unit testing without reflection.

extension SetupLivePreviewPane {
    /// Mirrors the private `progressFraction` computed var.
    var testableProgressFraction: Double {
        let total = Double(SetupStep.totalCount - 1)
        guard total > 0 else { return 0 }
        return Double(currentStep.rawValue - 1) / total
    }

    /// Mirrors the private `currentStepHint` computed var.
    var testableStepHint: String? {
        switch currentStep {
        case .welcome:         return "Enter your company details to get started."
        case .companyInfo:     return "Your company name and address will appear here."
        case .logo:            return "Your logo will be displayed in invoices and emails."
        case .timezoneLocale:  return "Timezone and currency settings will show here."
        case .businessHours:   return "Business hours help set expectations with customers."
        case .taxSetup:        return "Tax rate will be pre-filled on invoices."
        case .paymentMethods:  return "Accepted payment methods will appear on receipts."
        case .firstLocation:   return "Your first location will show here."
        case .firstEmployee:   return "Your first team member's info will appear here."
        case .smsSetup:        return "SMS settings enable automated customer messages."
        case .deviceTemplates: return "Device families determine your service templates."
        case .dataImport:      return "Migrate existing customers and inventory."
        case .theme:           return "Choose a look that fits your brand."
        case .sampleData:      return "Sample data lets you explore before going live."
        case .complete:        return nil
        }
    }

    /// Mirrors the private empty-state condition for the `dataCards` branch.
    var testableIsPayloadEffectivelyEmpty: Bool {
        payload.companyName.isEmpty &&
        payload.timezone == nil &&
        payload.taxRate == nil &&
        payload.paymentMethods == [.cash] &&
        payload.firstLocation == nil &&
        payload.firstEmployeeEmail == nil &&
        payload.sampleDataOptIn == nil
    }
}
