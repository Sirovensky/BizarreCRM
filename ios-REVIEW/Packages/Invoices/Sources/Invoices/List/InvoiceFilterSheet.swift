#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.1 InvoiceFilterSheet — 5-axis advanced filter
// Axes: date range / customer / amount range / payment method / created-by
// Follows the glass-bottom-sheet pattern established by LeadListFilterSheet.

public struct InvoiceFilterSheet: View {
    @Binding var filter: InvoiceListFilter

    @Environment(\.dismiss) private var dismiss

    // Local working copy — applied only when user taps Apply
    @State private var draft: InvoiceListFilter

    // Date picker expansion
    @State private var showDatePicker: Bool = false

    // Amount text fields (raw strings for keyboard input)
    @State private var amountMinText: String = ""
    @State private var amountMaxText: String = ""

    public init(filter: Binding<InvoiceListFilter>) {
        _filter = filter
        _draft = State(wrappedValue: filter.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                List {
                    dateRangeSection
                    customerSection
                    amountRangeSection
                    paymentMethodSection
                    createdBySection
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Filter Invoices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        draft = InvoiceListFilter()
                        amountMinText = ""
                        amountMaxText = ""
                    }
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Clear all invoice filters")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        commitAmountFields()
                        filter = draft
                        dismiss()
                    }
                    .bold()
                    .accessibilityLabel("Apply invoice filters")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Sync amount text from existing filter
            if let min = draft.amountMin { amountMinText = String(format: "%.2f", min) }
            if let max = draft.amountMax { amountMaxText = String(format: "%.2f", max) }
        }
    }

    // MARK: - Date range section

    private var dateRangeSection: some View {
        Section {
            // Quick presets
            HStack(spacing: BrandSpacing.sm) {
                ForEach(DatePreset.allCases, id: \.self) { preset in
                    Button {
                        let (start, end) = preset.dateRange
                        draft.dateRangeStart = start
                        draft.dateRangeEnd = end
                    } label: {
                        Text(preset.label)
                            .font(.brandLabelSmall())
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, BrandSpacing.xxs)
                            .foregroundStyle(isPresetSelected(preset) ? Color.black : .bizarreOnSurface)
                            .background(isPresetSelected(preset) ? Color.bizarreOrange : Color.bizarreSurface1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter by \(preset.label)")
                    .accessibilityAddTraits(isPresetSelected(preset) ? .isSelected : [])
                }
            }
            .padding(.vertical, BrandSpacing.xxs)
            .listRowBackground(Color.bizarreSurface1)

            // Custom range toggle
            Button {
                withAnimation { showDatePicker.toggle() }
            } label: {
                HStack {
                    Text("Custom range")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("Custom date range")

            if showDatePicker {
                DatePicker(
                    "From",
                    selection: Binding(
                        get: { draft.dateRangeStart ?? Date() },
                        set: { draft.dateRangeStart = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .font(.brandBodyMedium())
                .tint(.bizarreOrange)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityLabel("Filter start date")

                DatePicker(
                    "To",
                    selection: Binding(
                        get: { draft.dateRangeEnd ?? Date() },
                        set: { draft.dateRangeEnd = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .font(.brandBodyMedium())
                .tint(.bizarreOrange)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityLabel("Filter end date")
            }

            if draft.dateRangeStart != nil || draft.dateRangeEnd != nil {
                Button("Clear dates") {
                    draft.dateRangeStart = nil
                    draft.dateRangeEnd = nil
                }
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOrange)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityLabel("Clear date range filter")
            }
        } header: {
            Text("Date Range").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private func isPresetSelected(_ preset: DatePreset) -> Bool {
        let (start, end) = preset.dateRange
        return draft.dateRangeStart?.dayEqual(start) == true &&
               draft.dateRangeEnd?.dayEqual(end) == true
    }

    // MARK: - Customer section

    private var customerSection: some View {
        Section {
            HStack {
                Image(systemName: "person")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("Customer name", text: $draft.customerName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Filter by customer name")
                if !draft.customerName.isEmpty {
                    Button { draft.customerName = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear customer name filter")
                }
            }
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Customer").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Amount range section

    private var amountRangeSection: some View {
        Section {
            HStack(spacing: BrandSpacing.md) {
                HStack {
                    Text("$").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("Min", text: $amountMinText)
                        .font(.brandBodyMedium().monospacedDigit())
                        .keyboardType(.decimalPad)
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Minimum invoice amount in dollars")
                }
                Text("–").foregroundStyle(.bizarreOnSurfaceMuted)
                HStack {
                    Text("$").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("Max", text: $amountMaxText)
                        .font(.brandBodyMedium().monospacedDigit())
                        .keyboardType(.decimalPad)
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Maximum invoice amount in dollars")
                }
            }
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Amount Range").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Payment method section

    private var paymentMethodSection: some View {
        Section {
            // "Any" option
            Button {
                draft.paymentMethod = nil
            } label: {
                HStack {
                    Text("Any method")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    if draft.paymentMethod == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("Any payment method" + (draft.paymentMethod == nil ? ". Selected." : ""))

            ForEach(InvoicePaymentMethodFilter.allCases) { method in
                Button {
                    draft.paymentMethod = draft.paymentMethod == method.rawValue ? nil : method.rawValue
                } label: {
                    HStack {
                        Text(method.displayName)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        if draft.paymentMethod == method.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityLabel(method.displayName + (draft.paymentMethod == method.rawValue ? ". Selected." : ""))
            }
        } header: {
            Text("Payment Method").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Created-by section

    private var createdBySection: some View {
        Section {
            HStack {
                Image(systemName: "person.badge.clock")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("Employee name", text: $draft.createdBy)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Filter by employee who created the invoice")
                if !draft.createdBy.isEmpty {
                    Button { draft.createdBy = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear created-by filter")
                }
            }
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Created By").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Helpers

    private func commitAmountFields() {
        draft.amountMin = Double(amountMinText.replacingOccurrences(of: ",", with: "."))
        draft.amountMax = Double(amountMaxText.replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - Date preset helper

private enum DatePreset: CaseIterable {
    case today, last7, last30, thisMonth

    var label: String {
        switch self {
        case .today:     return "Today"
        case .last7:     return "7 days"
        case .last30:    return "30 days"
        case .thisMonth: return "This month"
        }
    }

    var dateRange: (start: Date, end: Date) {
        let now = Date()
        let cal = Calendar.current
        switch self {
        case .today:
            return (cal.startOfDay(for: now), now)
        case .last7:
            return (cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)) ?? now, now)
        case .last30:
            return (cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: now)) ?? now, now)
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps) ?? now
            return (start, now)
        }
    }
}

private extension Date {
    func dayEqual(_ other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
}
#endif
