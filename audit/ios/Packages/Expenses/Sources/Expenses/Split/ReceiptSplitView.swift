import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ReceiptSplitView

/// Displays OCR'd line items. User toggles each line's category assignment.
/// Tapping Save calls `POST /expenses/split` via the ViewModel.
public struct ReceiptSplitView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var vm: ReceiptSplitViewModel

    public init(ocrResult: ReceiptOCRResult, receiptId: String, api: APIClient) {
        _vm = State(wrappedValue: ReceiptSplitViewModel(ocrResult: ocrResult, receiptId: receiptId, api: api))
    }

    public var body: some View {
        NavigationStack {
            content
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
                .navigationTitle("Split Receipt")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                .onChange(of: vm.savedExpenseIds) { _, ids in
                    if ids != nil { dismiss() }
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.assignments.isEmpty {
            emptyState
        } else {
            lineItemList
        }
    }

    private var lineItemList: some View {
        List {
            Section {
                ForEach(vm.assignments) { assignment in
                    LineAssignmentRow(
                        assignment: assignment,
                        onToggle: { vm.setIncluded($0, for: assignment.id) },
                        onCategoryChange: { vm.setCategory($0, for: assignment.id) }
                    )
                }
            } header: {
                Text("Line items — assign categories")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.8)
            } footer: {
                if vm.totalIncludedCents > 0 {
                    Text("Total selected: \(formatCents(vm.totalIncludedCents))")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Total selected: \(formatCents(vm.totalIncludedCents))")
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No line items detected")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("OCR did not find itemized lines on this receipt.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel receipt split")
        }
        ToolbarItem(placement: .confirmationAction) {
            if vm.isSaving {
                ProgressView()
                    .accessibilityLabel("Saving split expenses")
            } else {
                Button("Save \(vm.includedCount > 0 ? "(\(vm.includedCount))" : "")") {
                    Task { await vm.save() }
                }
                .disabled(!vm.canSave)
                .brandGlass()
                .accessibilityLabel("Save \(vm.includedCount) expense records")
            }
        }
    }

    // MARK: - Helpers

    private func formatCents(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - LineAssignmentRow

private struct LineAssignmentRow: View {
    let assignment: LineAssignment
    let onToggle: (Bool) -> Void
    let onCategoryChange: (String) -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                Toggle("", isOn: Binding(
                    get: { assignment.included },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .accessibilityLabel(assignment.included ? "Exclude \(assignment.lineItem.description)" : "Include \(assignment.lineItem.description)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(assignment.lineItem.description)
                        .font(.brandBodyLarge())
                        .foregroundStyle(assignment.included ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
                        .lineLimit(2)
                    if let cents = assignment.lineItem.amountCents {
                        Text(formatCents(cents))
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOrange)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Category", selection: Binding(
                    get: { assignment.category },
                    set: { onCategoryChange($0) }
                )) {
                    ForEach(ReceiptSplitViewModel.availableCategories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(!assignment.included)
                .accessibilityLabel("Category: \(assignment.category). \(assignment.included ? "Tap to change." : "Include item to change category.")")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .opacity(assignment.included ? 1.0 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(assignment.lineItem.description). \(assignment.lineItem.amountCents.map { formatCents($0) } ?? ""). Category: \(assignment.category). \(assignment.included ? "Included." : "Excluded.")")
    }

    private func formatCents(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
