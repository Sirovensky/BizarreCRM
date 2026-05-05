import Foundation
import Core
import Networking

// MARK: - SetupDraft
//
// Codable snapshot of the wizard's in-progress state. Persisted to
// DraftStore (UserDefaults-backed) so that force-quit mid-wizard resumes
// from the same step instead of starting over.
//
// Screen key: "setup_wizard"  entityId: nil  (single global wizard per install)

public struct SetupDraft: Codable, Sendable {

    // MARK: Navigation

    public var currentStepRaw: Int
    public var completedSteps: [Int]

    // MARK: Company Info (step 2)

    public var companyName: String
    public var companyAddress: String
    public var companyPhone: String

    // MARK: Timezone/Locale (step 4)

    public var timezone: String?
    public var currency: String?
    public var locale: String?

    // MARK: Tax (step 6)

    public var taxName: String?
    public var taxRatePct: Double?
    public var taxApplyTo: String?

    // MARK: Payment methods (step 7)

    public var paymentMethods: [String]

    // MARK: First location (step 8)

    public var locationName: String?
    public var locationAddress: String?
    public var locationPhone: String?

    // MARK: Device templates + repair pricing (step 11)

    public var enabledDeviceFamilies: [String]?
    public var repairPricingMode: String?
    public var repairPricingTierDefaults: RepairPricingSeedPricing?
    public var repairPricingSpreadsheetPrices: [SetupSpreadsheetPriceDraft]?
    public var repairPricingAutoMarginPreset: String?
    public var repairPricingAutoMarginTargetType: String?
    public var repairPricingTargetMarginPct: Double?
    public var repairPricingTargetProfitAmount: Double?
    public var repairPricingCalculationBasis: String?
    public var repairPricingRoundingMode: String?
    public var repairPricingCapPct: Double?
    public var repairPricingAutoMarginRules: [RepairPricingAutoMarginRule]?

    // MARK: First employee (step 9+ / new step)

    public var firstEmployeeFirstName: String?
    public var firstEmployeeLastName: String?
    public var firstEmployeeEmail: String?
    public var firstEmployeeRole: String?

    // MARK: Sample data opt-in

    public var sampleDataOptIn: Bool?

    // MARK: Theme (step 12a)

    public var theme: String

    // MARK: Init

    public init(
        currentStepRaw: Int = 1,
        completedSteps: [Int] = [],
        companyName: String = "",
        companyAddress: String = "",
        companyPhone: String = "",
        timezone: String? = nil,
        currency: String? = nil,
        locale: String? = nil,
        taxName: String? = nil,
        taxRatePct: Double? = nil,
        taxApplyTo: String? = nil,
        paymentMethods: [String] = ["cash"],
        locationName: String? = nil,
        locationAddress: String? = nil,
        locationPhone: String? = nil,
        enabledDeviceFamilies: [String]? = nil,
        repairPricingMode: String? = nil,
        repairPricingTierDefaults: RepairPricingSeedPricing? = nil,
        repairPricingSpreadsheetPrices: [SetupSpreadsheetPriceDraft]? = nil,
        repairPricingAutoMarginPreset: String? = nil,
        repairPricingAutoMarginTargetType: String? = nil,
        repairPricingTargetMarginPct: Double? = nil,
        repairPricingTargetProfitAmount: Double? = nil,
        repairPricingCalculationBasis: String? = nil,
        repairPricingRoundingMode: String? = nil,
        repairPricingCapPct: Double? = nil,
        repairPricingAutoMarginRules: [RepairPricingAutoMarginRule]? = nil,
        firstEmployeeFirstName: String? = nil,
        firstEmployeeLastName: String? = nil,
        firstEmployeeEmail: String? = nil,
        firstEmployeeRole: String? = nil,
        sampleDataOptIn: Bool? = nil,
        theme: String = "system"
    ) {
        self.currentStepRaw = currentStepRaw
        self.completedSteps = completedSteps
        self.companyName = companyName
        self.companyAddress = companyAddress
        self.companyPhone = companyPhone
        self.timezone = timezone
        self.currency = currency
        self.locale = locale
        self.taxName = taxName
        self.taxRatePct = taxRatePct
        self.taxApplyTo = taxApplyTo
        self.paymentMethods = paymentMethods
        self.locationName = locationName
        self.locationAddress = locationAddress
        self.locationPhone = locationPhone
        self.enabledDeviceFamilies = enabledDeviceFamilies
        self.repairPricingMode = repairPricingMode
        self.repairPricingTierDefaults = repairPricingTierDefaults
        self.repairPricingSpreadsheetPrices = repairPricingSpreadsheetPrices
        self.repairPricingAutoMarginPreset = repairPricingAutoMarginPreset
        self.repairPricingAutoMarginTargetType = repairPricingAutoMarginTargetType
        self.repairPricingTargetMarginPct = repairPricingTargetMarginPct
        self.repairPricingTargetProfitAmount = repairPricingTargetProfitAmount
        self.repairPricingCalculationBasis = repairPricingCalculationBasis
        self.repairPricingRoundingMode = repairPricingRoundingMode
        self.repairPricingCapPct = repairPricingCapPct
        self.repairPricingAutoMarginRules = repairPricingAutoMarginRules
        self.firstEmployeeFirstName = firstEmployeeFirstName
        self.firstEmployeeLastName = firstEmployeeLastName
        self.firstEmployeeEmail = firstEmployeeEmail
        self.firstEmployeeRole = firstEmployeeRole
        self.sampleDataOptIn = sampleDataOptIn
        self.theme = theme
    }
}

// MARK: - SetupDraftStore

/// Thin facade over the shared DraftStore for setup-wizard-specific operations.
public actor SetupDraftStore {

    private let store: DraftStore
    private static let screen = "setup_wizard"

    public init(store: DraftStore = DraftStore()) {
        self.store = store
    }

    /// Persist a draft snapshot.
    public func save(_ draft: SetupDraft) async throws {
        try await store.save(draft, screen: Self.screen, entityId: nil)
    }

    /// Load the last saved draft, or `nil` if none.
    public func load() async throws -> SetupDraft? {
        try await store.load(SetupDraft.self, screen: Self.screen, entityId: nil)
    }

    /// Clear the draft on completion or deliberate reset.
    public func clear() async {
        await store.clear(screen: Self.screen, entityId: nil)
    }
}

// MARK: - SetupWizardViewModel draft helpers

public extension SetupWizardViewModel {

    /// Snapshot `wizardPayload` + navigation state into a `SetupDraft`.
    func makeDraft() -> SetupDraft {
        SetupDraft(
            currentStepRaw: currentStep.rawValue,
            completedSteps: Array(completedSteps),
            companyName:    wizardPayload.companyName,
            companyAddress: wizardPayload.companyAddress,
            companyPhone:   wizardPayload.companyPhone,
            timezone:  wizardPayload.timezone,
            currency:  wizardPayload.currency,
            locale:    wizardPayload.locale,
            taxName:   wizardPayload.taxRate?.name,
            taxRatePct: wizardPayload.taxRate?.ratePct,
            taxApplyTo: wizardPayload.taxRate?.applyTo.rawValue,
            paymentMethods: wizardPayload.paymentMethods.map(\.rawValue),
            locationName:    wizardPayload.firstLocation?.name,
            locationAddress: wizardPayload.firstLocation?.address,
            locationPhone:   wizardPayload.firstLocation?.phone,
            enabledDeviceFamilies: Array(wizardPayload.enabledDeviceFamilies).sorted(),
            repairPricingMode: wizardPayload.repairPricingMode.rawValue,
            repairPricingTierDefaults: wizardPayload.repairPricingTierDefaults,
            repairPricingSpreadsheetPrices: wizardPayload.repairPricingSpreadsheetPrices,
            repairPricingAutoMarginPreset: wizardPayload.repairPricingAutoMarginPreset.rawValue,
            repairPricingAutoMarginTargetType: wizardPayload.repairPricingAutoMarginTargetType.rawValue,
            repairPricingTargetMarginPct: wizardPayload.repairPricingTargetMarginPct,
            repairPricingTargetProfitAmount: wizardPayload.repairPricingTargetProfitAmount,
            repairPricingCalculationBasis: wizardPayload.repairPricingCalculationBasis.rawValue,
            repairPricingRoundingMode: wizardPayload.repairPricingRoundingMode.rawValue,
            repairPricingCapPct: wizardPayload.repairPricingCapPct,
            repairPricingAutoMarginRules: wizardPayload.repairPricingAutoMarginRules,
            firstEmployeeFirstName: wizardPayload.firstEmployeeFirstName,
            firstEmployeeLastName:  wizardPayload.firstEmployeeLastName,
            firstEmployeeEmail:     wizardPayload.firstEmployeeEmail,
            firstEmployeeRole:      wizardPayload.firstEmployeeRole,
            sampleDataOptIn: wizardPayload.sampleDataOptIn,
            theme:     wizardPayload.theme
        )
    }

    /// Restore navigation state and `wizardPayload` from a previously saved draft.
    func applyDraft(_ draft: SetupDraft) {
        if let step = SetupStep(rawValue: draft.currentStepRaw) {
            currentStep = step
        }
        completedSteps = Set(draft.completedSteps)

        wizardPayload.companyName    = draft.companyName
        wizardPayload.companyAddress = draft.companyAddress
        wizardPayload.companyPhone   = draft.companyPhone
        wizardPayload.timezone  = draft.timezone
        wizardPayload.currency  = draft.currency
        wizardPayload.locale    = draft.locale

        if let name = draft.taxName, let rate = draft.taxRatePct,
           let applyRaw = draft.taxApplyTo, let apply = TaxApply(rawValue: applyRaw) {
            wizardPayload.taxRate = TaxRate(name: name, ratePct: rate, applyTo: apply)
        }

        let methods: Set<PaymentMethod> = Set(
            draft.paymentMethods.compactMap { PaymentMethod(rawValue: $0) }
        )
        if !methods.isEmpty { wizardPayload.paymentMethods = methods }

        if let name = draft.locationName, let addr = draft.locationAddress {
            wizardPayload.firstLocation = SetupLocation(
                name: name, address: addr, phone: draft.locationPhone ?? ""
            )
        }

        if let families = draft.enabledDeviceFamilies {
            wizardPayload.enabledDeviceFamilies = Set(families)
        }
        if let modeRaw = draft.repairPricingMode,
           let mode = SetupRepairPricingMode(rawValue: modeRaw) {
            wizardPayload.repairPricingMode = mode
        }
        if let defaults = draft.repairPricingTierDefaults {
            wizardPayload.repairPricingTierDefaults = defaults
        }
        if let prices = draft.repairPricingSpreadsheetPrices {
            wizardPayload.repairPricingSpreadsheetPrices = prices
        }
        if let presetRaw = draft.repairPricingAutoMarginPreset,
           let preset = RepairPricingAutoMarginPreset(rawValue: presetRaw) {
            wizardPayload.repairPricingAutoMarginPreset = preset
        }
        if let targetTypeRaw = draft.repairPricingAutoMarginTargetType,
           let targetType = RepairPricingAutoMarginTargetType(rawValue: targetTypeRaw) {
            wizardPayload.repairPricingAutoMarginTargetType = targetType
        }
        if let targetMarginPct = draft.repairPricingTargetMarginPct {
            wizardPayload.repairPricingTargetMarginPct = targetMarginPct
        }
        if let targetProfitAmount = draft.repairPricingTargetProfitAmount {
            wizardPayload.repairPricingTargetProfitAmount = targetProfitAmount
        }
        if let basisRaw = draft.repairPricingCalculationBasis,
           let basis = RepairPricingAutoMarginBasis(rawValue: basisRaw) {
            wizardPayload.repairPricingCalculationBasis = basis
        }
        if let roundingRaw = draft.repairPricingRoundingMode,
           let roundingMode = RepairPricingRoundingMode(rawValue: roundingRaw) {
            wizardPayload.repairPricingRoundingMode = roundingMode
        }
        if let capPct = draft.repairPricingCapPct {
            wizardPayload.repairPricingCapPct = capPct
        }
        if let rules = draft.repairPricingAutoMarginRules {
            wizardPayload.repairPricingAutoMarginRules = rules
        }

        wizardPayload.firstEmployeeFirstName = draft.firstEmployeeFirstName
        wizardPayload.firstEmployeeLastName  = draft.firstEmployeeLastName
        wizardPayload.firstEmployeeEmail     = draft.firstEmployeeEmail
        wizardPayload.firstEmployeeRole      = draft.firstEmployeeRole
        wizardPayload.sampleDataOptIn = draft.sampleDataOptIn

        wizardPayload.theme = draft.theme
    }

    /// Load a saved draft (if any) and resume from where the user left off.
    func resumeFromDraft(draftStore: SetupDraftStore) async {
        do {
            if let draft = try await draftStore.load() {
                applyDraft(draft)
                AppLog.ui.info("Setup wizard resumed from draft at step \(draft.currentStepRaw, privacy: .public)")
            }
        } catch {
            AppLog.ui.warning("Failed to load setup draft: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Persist current state as a draft.
    func saveDraft(to draftStore: SetupDraftStore) async {
        do {
            try await draftStore.save(makeDraft())
        } catch {
            AppLog.ui.warning("Failed to save setup draft: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clear the draft (call after successful wizard completion or deliberate reset).
    func clearDraft(from draftStore: SetupDraftStore) async {
        await draftStore.clear()
    }
}
