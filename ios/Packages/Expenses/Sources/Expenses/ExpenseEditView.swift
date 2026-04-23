import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class ExpenseEditViewModel {

    // MARK: Form state (populated from existing expense on load)

    public var category: String = ""
    public var amountText: String = ""
    public var vendor: String = ""
    public var taxAmountText: String = ""
    public var paymentMethod: String = ""
    public var descriptionText: String = ""
    public var notes: String = ""
    public var date: Date = Date()
    public var isReimbursable: Bool = false

    // MARK: Load / submit state

    public enum LoadState: Sendable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var loadState: LoadState = .loading
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSave: Bool = false

    public var isLoaded: Bool {
        if case .loaded = loadState { return true }
        return false
    }

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let expenseId: Int64

    public init(api: APIClient, expenseId: Int64) {
        self.api = api
        self.expenseId = expenseId
    }

    // MARK: - Computed

    public var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }
    public var taxAmount: Double? {
        let t = taxAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : Double(t.replacingOccurrences(of: ",", with: "."))
    }

    public var isValid: Bool {
        !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (amount ?? 0) > 0 && (amount ?? 0) <= 100_000
            && (taxAmount == nil || (taxAmount! >= 0 && taxAmount! <= 100_000))
    }

    // MARK: - Load existing expense

    public func load() async {
        loadState = .loading
        do {
            let expense = try await api.getExpense(id: expenseId)
            populate(from: expense)
            loadState = .loaded
        } catch {
            AppLog.ui.error("Expense edit load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    private func populate(from expense: Expense) {
        category = expense.category ?? ""
        amountText = expense.amount.map { String(format: "%.2f", $0) } ?? ""
        vendor = expense.vendor ?? ""
        taxAmountText = expense.taxAmount.map { String(format: "%.2f", $0) } ?? ""
        paymentMethod = expense.paymentMethod ?? ""
        descriptionText = expense.description ?? ""
        notes = expense.notes ?? ""
        isReimbursable = expense.isReimbursable ?? false

        if let dateStr = expense.date,
           let parsed = Self.parseISODate(dateStr) {
            date = parsed
        } else {
            date = Date()
        }
    }

    private static func parseISODate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    // MARK: - Save

    public func save() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        guard isValid, let amount else {
            errorMessage = "Category and a positive amount up to $100,000 are required."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let isoDate: String = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }()

        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPayment = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)

        let req = UpdateExpenseRequest(
            category: category.trimmingCharacters(in: .whitespaces),
            amount: amount,
            description: trimmedDesc.isEmpty ? nil : trimmedDesc,
            date: isoDate,
            vendor: trimmedVendor.isEmpty ? nil : trimmedVendor,
            taxAmount: taxAmount,
            paymentMethod: trimmedPayment.isEmpty ? nil : trimmedPayment,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            isReimbursable: isReimbursable
        )

        do {
            _ = try await api.updateExpense(id: expenseId, body: req)
            didSave = true
        } catch {
            AppLog.ui.error("Expense update failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct ExpenseEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExpenseEditViewModel

    public init(api: APIClient, expenseId: Int64) {
        _vm = State(wrappedValue: ExpenseEditViewModel(api: api, expenseId: expenseId))
    }

    public var body: some View {
        NavigationStack {
            body_content
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
                .navigationTitle("Edit Expense")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarItems }
                .task { await vm.load() }
        }
    }

    @ViewBuilder
    private var body_content: some View {
        switch vm.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading expense")
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load expense")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Retry loading expense")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            formContent
        }
    }

    private var formContent: some View {
        Form {
            amountSection
            categorySection
            vendorPaymentSection
            dateReimbursableSection
            notesSection
            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
            }
        }
    }

    private var amountSection: some View {
        Section("Amount") {
            HStack {
                Text("$").foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $vm.amountText)
                    #if canImport(UIKit)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Expense amount in US dollars")
            }
            HStack {
                Text("Tax $").foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00 (optional)", text: $vm.taxAmountText)
                    #if canImport(UIKit)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel("Tax amount")
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var categorySection: some View {
        Section("Category") {
            Picker("Category", selection: $vm.category) {
                Text("Select category").tag("")
                    .accessibilityLabel("No category selected")
                ForEach(ExpenseCategory.allCases, id: \.rawValue) { cat in
                    Text(cat.rawValue).tag(cat.rawValue)
                }
            }
            .accessibilityLabel("Expense category picker")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var vendorPaymentSection: some View {
        Section("Vendor & Payment") {
            TextField("Vendor / Merchant", text: $vm.vendor)
                #if canImport(UIKit)
                .textInputAutocapitalization(.words)
                #endif
                .accessibilityLabel("Vendor or merchant name")
            Picker("Payment Method", selection: $vm.paymentMethod) {
                Text("Select method").tag("")
                    .accessibilityLabel("No payment method selected")
                ForEach(PaymentMethod.allCases, id: \.rawValue) { method in
                    Text(method.rawValue).tag(method.rawValue)
                }
            }
            .accessibilityLabel("Payment method picker")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var dateReimbursableSection: some View {
        Section("Date & Reimbursable") {
            DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                .accessibilityLabel("Expense date")
            Toggle(isOn: $vm.isReimbursable) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reimbursable")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Request reimbursement from employer")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .tint(.bizarreOrange)
            .accessibilityLabel("Mark as reimbursable expense")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var notesSection: some View {
        Section("Description & Notes") {
            TextField("What was it for?", text: $vm.descriptionText, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityLabel("Expense description")
            TextField("Internal notes (optional)", text: $vm.notes, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityLabel("Internal notes")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("expenses.edit.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(vm.isSubmitting ? "Saving…" : "Save") {
                Task {
                    await vm.save()
                    if vm.didSave { dismiss() }
                }
            }
            .disabled(!vm.isValid || vm.isSubmitting || !vm.isLoaded)
            .accessibilityIdentifier("expenses.edit.save")
        }
    }
}
