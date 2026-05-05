#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - RecurringChargeRule

/// Describes the cadence of a recurring charge attached to the cart.
///
/// After the cashier selects a frequency and confirms, this value is stored
/// on the cart (`Cart.recurringRule`) and forwarded to the invoice creation
/// endpoint as `recurring_rule` so the server can schedule future charges.
///
/// - SeeAlso: `PosRecurringChargeSheet`, `Cart.setRecurringRule(_:)`
public struct RecurringChargeRule: Equatable, Sendable, Codable {
    /// Human-readable label for the frequency chip (e.g. "Weekly").
    public let frequencyLabel: String
    /// API-level key sent to the server (e.g. "weekly", "monthly").
    public let frequencyKey: String
    /// Optional day-of-month for monthly / quarterly frequencies (1–28).
    public let dayOfMonth: Int?
    /// Optional ISO-8601 date string for a schedule end date (nil = indefinite).
    public let endDate: String?

    public init(
        frequencyLabel: String,
        frequencyKey: String,
        dayOfMonth: Int? = nil,
        endDate: String? = nil
    ) {
        self.frequencyLabel = frequencyLabel
        self.frequencyKey = frequencyKey
        self.dayOfMonth = dayOfMonth
        self.endDate = endDate
    }
}

// MARK: - PosRecurringChargeSheet

/// §16 — Recurring-charge selector sheet.
///
/// Lets the cashier mark a POS cart as the first occurrence of a recurring
/// billing series (weekly / bi-weekly / monthly / quarterly / yearly).
/// The selection is stored in `Cart.recurringRule` and printed on the
/// receipt as a "Recurring: Monthly" line. Future charges are handled
/// server-side by `POST /invoices/recurring`.
///
/// Layout:
///   - Frequency chips row (scrollable, 5 presets)
///   - Day-of-month picker (only for monthly / quarterly)
///   - End-date toggle + DatePicker (optional)
///   - Active summary card ("Charges monthly · starting today")
///   - Cancel / Apply buttons
///
/// Offline: local-only; the rule is queued with the invoice on reconnect.
/// Glass: none — sheet content is plain `surface`; only the Apply CTA uses
/// the primary cream fill (brand convention for action buttons).
struct PosRecurringChargeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var cart: Cart

    // MARK: - Frequency options

    private struct FrequencyOption: Identifiable {
        let id = UUID()
        let label: String
        let key: String
        let hasDayPicker: Bool
    }

    private let options: [FrequencyOption] = [
        FrequencyOption(label: "Weekly",      key: "weekly",      hasDayPicker: false),
        FrequencyOption(label: "Bi-weekly",   key: "biweekly",    hasDayPicker: false),
        FrequencyOption(label: "Monthly",     key: "monthly",     hasDayPicker: true),
        FrequencyOption(label: "Quarterly",   key: "quarterly",   hasDayPicker: true),
        FrequencyOption(label: "Yearly",      key: "yearly",      hasDayPicker: false),
    ]

    // MARK: - State

    @State private var selectedKey: String = "monthly"
    @State private var dayOfMonth: Int = 1
    @State private var useEndDate: Bool = false
    @State private var endDate: Date = Calendar.current.date(
        byAdding: .year, value: 1, to: Date()
    ) ?? Date()

    private var selectedOption: FrequencyOption? {
        options.first { $0.key == selectedKey }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        frequencyChips
                        if selectedOption?.hasDayPicker == true {
                            dayOfMonthPicker
                        }
                        endDateToggle
                        summaryCard
                        Spacer(minLength: BrandSpacing.xl)
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.md)
                }
            }
            .navigationTitle("Recurring charge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("pos.recurring.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyRule()
                    }
                    .font(.brandLabelLarge().weight(.semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityIdentifier("pos.recurring.apply")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Pre-fill from existing rule if the sheet is re-opened.
            if let existing = cart.recurringRule {
                selectedKey  = existing.frequencyKey
                dayOfMonth   = existing.dayOfMonth ?? 1
                if let end = existing.endDate,
                   let date = ISO8601DateFormatter().date(from: end) {
                    useEndDate = true
                    endDate = date
                }
            }
        }
    }

    // MARK: - Frequency chips

    private var frequencyChips: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Frequency")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textCase(.uppercase)
                .kerning(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(options) { option in
                        let isSelected = selectedKey == option.key
                        Button {
                            BrandHaptics.tap()
                            withAnimation(BrandMotion.snappy) { selectedKey = option.key }
                        } label: {
                            Text(option.label)
                                .font(.brandLabelLarge())
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundStyle(isSelected ? Color.bizarreOnOrange : .bizarreOnSurface)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.sm)
                                .background(
                                    isSelected
                                        ? Color.bizarreOrange
                                        : Color.bizarreSurface2.opacity(0.7),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        isSelected ? Color.clear : Color.bizarreOutline.opacity(0.5),
                                        lineWidth: 0.5
                                    )
                                )
                                .scaleEffect(isSelected ? 1.04 : 1.0)
                                .animation(BrandMotion.snappy, value: isSelected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityLabel("\(option.label), \(isSelected ? "selected" : "not selected")")
                        .accessibilityIdentifier("pos.recurring.chip.\(option.key)")
                    }
                }
                .padding(.vertical, BrandSpacing.xxs)
            }
        }
    }

    // MARK: - Day of month picker

    private var dayOfMonthPicker: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Charge on day")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textCase(.uppercase)
                .kerning(0.8)

            Picker("Day of month", selection: $dayOfMonth) {
                ForEach(1...28, id: \.self) { day in
                    Text(ordinal(day)).tag(day)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
            .clipped()
            .background(
                Color.bizarreSurface2.opacity(0.6),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            )
            .accessibilityLabel("Day of month picker")
            .accessibilityIdentifier("pos.recurring.dayPicker")
        }
    }

    // MARK: - End date toggle

    private var endDateToggle: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Toggle(isOn: $useEndDate.animation(BrandMotion.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set end date")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Leave off for indefinite recurring")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .tint(.bizarreOrange)
            .accessibilityIdentifier("pos.recurring.endDateToggle")

            if useEndDate {
                DatePicker(
                    "End date",
                    selection: $endDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(.bizarreOrange)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier("pos.recurring.endDatePicker")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(
            Color.bizarreSurface1,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
        )
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(summaryTitle)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(summaryDetail)
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreOrange.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summaryTitle). \(summaryDetail)")
        .accessibilityIdentifier("pos.recurring.summaryCard")
    }

    private var summaryTitle: String {
        guard let opt = selectedOption else { return "Recurring charge" }
        return "Charges \(opt.label.lowercased())"
    }

    private var summaryDetail: String {
        var parts: [String] = ["Starting today"]
        if let opt = selectedOption, opt.hasDayPicker {
            parts.append("on the \(ordinal(dayOfMonth)) of each period")
        }
        if useEndDate {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            parts.append("until \(fmt.string(from: endDate))")
        } else {
            parts.append("indefinitely")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Apply

    private func applyRule() {
        guard let opt = selectedOption else { return }
        let endISO: String? = useEndDate
            ? ISO8601DateFormatter().string(from: endDate)
            : nil
        let rule = RecurringChargeRule(
            frequencyLabel: opt.label,
            frequencyKey: opt.key,
            dayOfMonth: opt.hasDayPicker ? dayOfMonth : nil,
            endDate: endISO
        )
        cart.setRecurringRule(rule)
        BrandHaptics.success()
        dismiss()
    }

    // MARK: - Helpers

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 10 {
        case 1 where n % 100 != 11: suffix = "st"
        case 2 where n % 100 != 12: suffix = "nd"
        case 3 where n % 100 != 13: suffix = "rd"
        default:                     suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
#endif
