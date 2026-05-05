#if canImport(UIKit)
import Foundation

// MARK: - TicketDraft
//
// Immutable value type accumulated as the repair flow advances.
// Each step returns a new copy with its fields filled in — never mutate
// the existing struct (coding-style rule: ALWAYS create new objects).

/// Device condition as received from the customer.
public enum DeviceCondition: String, CaseIterable, Sendable, Equatable {
    case excellent = "Excellent"
    case good      = "Good"
    case fair      = "Fair"
    case poor      = "Poor"

    public var displayName: String { rawValue }
}

/// Quick-pick symptom chips shown on the describe-issue step.
public enum RepairSymptomChip: String, CaseIterable, Sendable, Equatable {
    case screenCracked  = "Screen cracked"
    case wontCharge     = "Won't charge"
    case waterDamage    = "Water damage"
    case battery        = "Battery"
    case other          = "Other"

    public var displayLabel: String { rawValue }

    /// SF Symbol for the chip icon.
    public var systemImage: String {
        switch self {
        case .screenCracked: return "display"
        case .wontCharge:    return "bolt.slash"
        case .waterDamage:   return "drop.triangle"
        case .battery:       return "battery.0percent"
        case .other:         return "questionmark.circle"
        }
    }
}

/// Parts/labor line item on the quote step.
public struct RepairQuoteLine: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    /// Unit price in cents.
    public let priceCents: Int
    public let isIncluded: Bool
    /// When `true` this line came from the BOM resolver (Agent F).
    public let isPrePopulated: Bool
    /// Optional subtitle shown beneath the name: stock info, estimated time, etc.
    /// Examples: "OEM grade · 22 in stock", "~45 min", "3 in stock — low"
    public let subtitle: String?

    public init(
        id: UUID = UUID(),
        name: String,
        priceCents: Int,
        isIncluded: Bool = true,
        isPrePopulated: Bool = false,
        subtitle: String? = nil
    ) {
        self.id = id
        self.name = name
        self.priceCents = priceCents
        self.isIncluded = isIncluded
        self.isPrePopulated = isPrePopulated
        self.subtitle = subtitle
    }

    /// Returns a copy with `isIncluded` toggled.
    public func toggled() -> RepairQuoteLine {
        RepairQuoteLine(
            id: id,
            name: name,
            priceCents: priceCents,
            isIncluded: !isIncluded,
            isPrePopulated: isPrePopulated,
            subtitle: subtitle
        )
    }
}

/// Accumulated state carried through all four repair-flow steps.
/// Every `withXxx` factory returns a NEW value — never an in-place mutation.
public struct TicketDraft: Sendable, Equatable {

    // MARK: Step 1 — Device
    public let customerId: Int64
    public let selectedDeviceOption: PosDeviceOption?

    // MARK: Step 2 — Symptom
    public let symptomText: String
    public let condition: DeviceCondition?
    public let quickChips: Set<RepairSymptomChip>
    public let internalNotes: String

    // MARK: Step 3 — Quote
    public let diagnosticNotes: String
    public let quoteLines: [RepairQuoteLine]

    // MARK: Step 4 — Deposit
    /// Default deposit: 15% of total (editable). Stored in cents.
    public let depositCents: Int

    // MARK: - Init

    public init(customerId: Int64) {
        self.customerId = customerId
        self.selectedDeviceOption = nil
        self.symptomText = ""
        self.condition = nil
        self.quickChips = []
        self.internalNotes = ""
        self.diagnosticNotes = ""
        self.quoteLines = []
        self.depositCents = 0
    }

    private init(
        customerId: Int64,
        selectedDeviceOption: PosDeviceOption?,
        symptomText: String,
        condition: DeviceCondition?,
        quickChips: Set<RepairSymptomChip>,
        internalNotes: String,
        diagnosticNotes: String,
        quoteLines: [RepairQuoteLine],
        depositCents: Int
    ) {
        self.customerId = customerId
        self.selectedDeviceOption = selectedDeviceOption
        self.symptomText = symptomText
        self.condition = condition
        self.quickChips = quickChips
        self.internalNotes = internalNotes
        self.diagnosticNotes = diagnosticNotes
        self.quoteLines = quoteLines
        self.depositCents = depositCents
    }

    // MARK: - Immutable setters

    public func withDevice(_ option: PosDeviceOption) -> TicketDraft {
        TicketDraft(
            customerId: customerId,
            selectedDeviceOption: option,
            symptomText: symptomText,
            condition: condition,
            quickChips: quickChips,
            internalNotes: internalNotes,
            diagnosticNotes: diagnosticNotes,
            quoteLines: quoteLines,
            depositCents: depositCents
        )
    }

    public func withSymptom(
        text: String,
        condition: DeviceCondition?,
        chips: Set<RepairSymptomChip>,
        internalNotes: String
    ) -> TicketDraft {
        TicketDraft(
            customerId: customerId,
            selectedDeviceOption: selectedDeviceOption,
            symptomText: text,
            condition: condition,
            quickChips: chips,
            internalNotes: internalNotes,
            diagnosticNotes: diagnosticNotes,
            quoteLines: quoteLines,
            depositCents: depositCents
        )
    }

    public func withQuote(diagnosticNotes: String, lines: [RepairQuoteLine]) -> TicketDraft {
        TicketDraft(
            customerId: customerId,
            selectedDeviceOption: selectedDeviceOption,
            symptomText: symptomText,
            condition: condition,
            quickChips: quickChips,
            internalNotes: internalNotes,
            diagnosticNotes: diagnosticNotes,
            quoteLines: lines,
            depositCents: depositCents
        )
    }

    public func withDeposit(cents: Int) -> TicketDraft {
        TicketDraft(
            customerId: customerId,
            selectedDeviceOption: selectedDeviceOption,
            symptomText: symptomText,
            condition: condition,
            quickChips: quickChips,
            internalNotes: internalNotes,
            diagnosticNotes: diagnosticNotes,
            quoteLines: quoteLines,
            depositCents: cents
        )
    }

    // MARK: - Derived

    /// Running estimate: sum of included quote lines (cents).
    public var estimateCents: Int {
        quoteLines
            .filter { $0.isIncluded }
            .reduce(0) { $0 + $1.priceCents }
    }

    /// Suggested default deposit (15% of estimate, rounded to nearest cent).
    public var suggestedDepositCents: Int {
        Int((Double(estimateCents) * 0.15).rounded())
    }

    /// Balance remaining after deposit (cents).
    public var balanceDueCents: Int {
        max(0, estimateCents - depositCents)
    }

    /// Validation: step 1 requires a device option to be selected.
    public var isDeviceStepValid: Bool {
        selectedDeviceOption != nil
    }

    /// Validation: step 2 requires a non-empty symptom description.
    public var isSymptomStepValid: Bool {
        !symptomText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Validation: deposit must be ≥ 0 and ≤ estimate.
    public var isDepositStepValid: Bool {
        depositCents >= 0 && depositCents <= estimateCents
    }
}
#endif
