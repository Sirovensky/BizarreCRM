#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §8.1 Estimate list filters
//
// Sheet containing:
//   • Date range picker (created_at from/to)
//   • Customer name filter (free-text)
//   • Amount range (min / max)
//   • Validity filter (valid_until from/to)
//
// The parent view reads `EstimateListFilters` and passes it into the
// EstimateListViewModel which rebuilds its fetch query.

// MARK: - EstimateListFilters

/// Value type carrying all active list filters.
public struct EstimateListFilters: Equatable, Sendable {
    public var dateFrom: Date?
    public var dateTo: Date?
    public var customerKeyword: String = ""
    public var amountMin: String = ""
    public var amountMax: String = ""
    public var validFrom: Date?
    public var validTo: Date?

    public init() {}

    /// Returns true when any field carries a non-default value.
    public var isActive: Bool {
        dateFrom != nil || dateTo != nil ||
        !customerKeyword.trimmingCharacters(in: .whitespaces).isEmpty ||
        !amountMin.isEmpty || !amountMax.isEmpty ||
        validFrom != nil || validTo != nil
    }

    /// Flat badge count for the filter button badge.
    public var activeCount: Int {
        var n = 0
        if dateFrom != nil || dateTo != nil { n += 1 }
        if !customerKeyword.trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
        if !amountMin.isEmpty || !amountMax.isEmpty { n += 1 }
        if validFrom != nil || validTo != nil { n += 1 }
        return n
    }
}

// MARK: - EstimateListFiltersView

/// Full-screen sheet for configuring estimate list filters.
/// Presented via `.sheet(isPresented:) { EstimateListFiltersView(...) }`.
public struct EstimateListFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: EstimateListFilters
    @State private var draft: EstimateListFilters

    public init(filters: Binding<EstimateListFilters>) {
        self._filters = filters
        self._draft = State(initialValue: filters.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: Date range
                Section("Date created") {
                    datePicker("From", selection: $draft.dateFrom)
                    datePicker("To",   selection: $draft.dateTo)
                }

                // MARK: Customer
                Section("Customer") {
                    HStack {
                        Image(systemName: "person")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        TextField("Customer name or phone", text: $draft.customerKeyword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                // MARK: Amount range
                Section("Amount") {
                    HStack {
                        Text("Min")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .font(.brandBodyMedium())
                        Spacer()
                        TextField("$0.00", text: $draft.amountMin)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .frame(maxWidth: 100)
                            .accessibilityLabel("Minimum amount")
                    }
                    HStack {
                        Text("Max")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .font(.brandBodyMedium())
                        Spacer()
                        TextField("No limit", text: $draft.amountMax)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .frame(maxWidth: 100)
                            .accessibilityLabel("Maximum amount")
                    }
                }

                // MARK: Validity window
                Section("Valid until") {
                    datePicker("From", selection: $draft.validFrom)
                    datePicker("To",   selection: $draft.validTo)
                }

                // MARK: Reset
                if draft.isActive {
                    Section {
                        Button("Clear all filters", role: .destructive) {
                            draft = EstimateListFilters()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filters = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.bizarreOrange)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func datePicker(_ label: String, selection: Binding<Date?>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.bizarreOnSurface)
                .font(.brandBodyMedium())
            Spacer()
            if let date = selection.wrappedValue {
                Button {
                    selection.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(label) date")
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date },
                        set: { selection.wrappedValue = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
            } else {
                Button {
                    selection.wrappedValue = Date()
                } label: {
                    Text("Set date")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set \(label) date")
            }
        }
    }
}

#endif
