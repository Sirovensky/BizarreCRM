#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.9 Installment Plan Editor Sheet — split invoice into N installments

@MainActor
@Observable
final class InstallmentPlanEditorViewModel {

    // MARK: - Form state

    var count: Int = 3 { didSet { rebuildItems() } }
    var startDate: Date = Calendar.current.date(byAdding: .month, value: 0, to: .now) ?? .now {
        didSet { rebuildItems() }
    }
    var interval: Calendar.Component = .month { didSet { rebuildItems() } }
    var autopay: Bool = false

    /// Computed items from the calculator; user can adjust individual amounts.
    var items: [MutableInstallmentItem] = []
    var isSubmitting: Bool = false
    var errorMessage: String?
    var didSave: Bool = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let invoiceId: Int64
    @ObservationIgnored private let totalCents: Int

    init(api: APIClient, invoiceId: Int64, totalCents: Int) {
        self.api = api
        self.invoiceId = invoiceId
        self.totalCents = totalCents
        rebuildItems()
    }

    // MARK: - Derived

    var sumCents: Int { items.reduce(0) { $0 + $1.amountCents } }
    var isBalanced: Bool { sumCents == totalCents }
    var isValid: Bool { isBalanced && items.allSatisfy { $0.amountCents > 0 } }
    var imbalanceCents: Int { sumCents - totalCents }

    // MARK: - Mutations

    private func rebuildItems() {
        let computed = InstallmentCalculator.distribute(
            totalCents: totalCents,
            count: count,
            startDate: startDate,
            interval: interval
        )
        items = computed.map { MutableInstallmentItem(item: $0) }
    }

    func save() async {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let ymd = DateFormatter.yyyyMMdd
        let requestItems = items.map {
            CreateInstallmentPlanRequest.ItemRequest(
                dueDate: ymd.string(from: $0.dueDate),
                amountCents: $0.amountCents
            )
        }
        let req = CreateInstallmentPlanRequest(
            invoiceId: invoiceId,
            installments: requestItems,
            autopay: autopay
        )

        do {
            _ = try await api.post(
                "/api/v1/invoices/\(invoiceId)/installment-plans",
                body: req,
                as: InstallmentPlan.self
            )
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Mutable wrapper for a computed item so the user can adjust amounts.
final class MutableInstallmentItem: Identifiable, ObservableObject {
    let id = UUID()
    var dueDate: Date
    var amountCents: Int

    init(item: ComputedInstallmentItem) {
        self.dueDate = item.dueDate
        self.amountCents = item.amountCents
    }
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

public struct InstallmentPlanEditorSheet: View {
    @State private var vm: InstallmentPlanEditorViewModel
    @Environment(\.dismiss) private var dismiss
    private let onSaved: () async -> Void

    private let intervalOptions: [(Calendar.Component, String)] = [
        (.month, "Monthly"),
        (.weekOfYear, "Weekly"),
        (.year, "Yearly")
    ]

    public init(
        api: APIClient,
        invoiceId: Int64,
        totalCents: Int,
        onSaved: @escaping () async -> Void
    ) {
        _vm = State(wrappedValue: InstallmentPlanEditorViewModel(
            api: api,
            invoiceId: invoiceId,
            totalCents: totalCents
        ))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Plan settings") {
                    Stepper("Installments: \(vm.count)", value: $vm.count, in: 2...36)
                        .accessibilityLabel("Number of installments, \(vm.count)")

                    Picker("Interval", selection: $vm.interval) {
                        ForEach(intervalOptions, id: \.0.hashValue) { opt in
                            Text(opt.1).tag(opt.0)
                        }
                    }
                    .accessibilityLabel("Payment interval")

                    DatePicker("First payment", selection: $vm.startDate, displayedComponents: .date)
                        .accessibilityLabel("First installment due date")

                    Toggle("Autopay", isOn: $vm.autopay)
                        .accessibilityLabel("Automatically charge on due dates")
                }

                Section("Schedule") {
                    ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, item in
                        InstallmentItemRow(index: index + 1, item: item)
                    }

                    HStack {
                        Text("Total")
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(formatMoney(vm.sumCents))
                            .font(.brandBodyLarge())
                            .foregroundStyle(vm.isBalanced ? .bizarreOnSurface : .bizarreError)
                            .monospacedDigit()
                    }

                    if !vm.isBalanced {
                        Text("Off by \(formatMoney(abs(vm.imbalanceCents))). Adjust amounts to match invoice total \(formatMoney(vm.totalCents)).")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .accessibilityLabel("Schedule total does not match invoice total")
                    }
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                    }
                }
            }
            .navigationTitle("Payment Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Plan") {
                        Task {
                            await vm.save()
                            if vm.didSave {
                                await onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Row

private struct InstallmentItemRow: View {
    let index: Int
    @ObservedObject var item: MutableInstallmentItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Installment \(index)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                DatePicker("", selection: $item.dueDate, displayedComponents: .date)
                    .labelsHidden()
                    .font(.brandBodyMedium())
                    .accessibilityLabel("Due date for installment \(index)")
            }
            Spacer()
            TextField(
                "Amount",
                value: $item.amountCents,
                format: .number
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .monospacedDigit()
            .accessibilityLabel("Amount in cents for installment \(index)")

            Text("¢")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}

private func formatMoney(_ cents: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents)"
}
#endif
