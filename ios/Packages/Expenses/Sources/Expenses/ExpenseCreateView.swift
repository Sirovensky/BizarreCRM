import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class ExpenseCreateViewModel {
    public var category: String = ""
    public var amountText: String = ""
    public var description: String = ""
    public var date: Date = Date()

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    public var isValid: Bool {
        !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (amount ?? 0) > 0 && (amount ?? 0) <= 100_000
    }

    public func submit() async {
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
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let req = CreateExpenseRequest(
            category: category.trimmingCharacters(in: .whitespaces),
            amount: amount,
            description: trimmedDesc.isEmpty ? nil : trimmedDesc,
            date: isoDate
        )

        do {
            let created = try await api.createExpense(req)
            createdId = created.id
        } catch {
            AppLog.ui.error("Expense create failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct ExpenseCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExpenseCreateViewModel

    public init(api: APIClient) { _vm = State(wrappedValue: ExpenseCreateViewModel(api: api)) }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Category", text: $vm.category)
                        .textInputAutocapitalization(.words)
                    TextField("Amount (USD)", text: $vm.amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                }
                Section("Description") {
                    TextField("What was it for?", text: $vm.description, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let err = vm.errorMessage {
                    Section { Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.createdId != nil { dismiss() }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
        }
    }
}
