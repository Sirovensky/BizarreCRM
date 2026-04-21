import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import Camera
import UIKit
#endif

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
    /// Set to `true` while OCR is running so we can show a spinner.
    public private(set) var isOCRRunning: Bool = false
    /// Non-nil while the receipt picker sheet is presented.
    public var showingReceiptPicker: Bool = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

#if canImport(UIKit)
    /// Called after `PhotoCaptureView` delivers images. Runs OCR on the first
    /// image; if a total is found, pre-fills `amountText`.
    @MainActor
    public func handleCapturedImages(_ images: [UIImage]) async {
        showingReceiptPicker = false
        guard let first = images.first else { return }
        isOCRRunning = true
        defer { isOCRRunning = false }
        if let total = await ReceiptEdgeDetector.ocrTotal(first) {
            let formatted = String(format: "%.2f", total)
            // Only pre-fill if user hasn't typed a value yet.
            if amountText.isEmpty || (Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) == 0 {
                amountText = formatted
            }
        }
    }
#endif

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
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.words)
                        #endif
                        .accessibilityLabel("Expense category")
                    TextField("Amount (USD)", text: $vm.amountText)
                        #if canImport(UIKit)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel("Expense amount in US dollars")
                    DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                        .accessibilityLabel("Expense date")
                }
                Section("Description") {
                    TextField("What was it for?", text: $vm.description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Expense description")
                }
                Section {
                    receiptAttachButton
                }
                if let err = vm.errorMessage {
                    Section { Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New expense")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isOCRRunning {
                        ProgressView()
                            .accessibilityLabel("Reading receipt amount")
                    } else {
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
        #if canImport(UIKit)
        .sheet(isPresented: $vm.showingReceiptPicker) {
            PhotoCaptureView { images in
                Task { await vm.handleCapturedImages(images) }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
    }

    @ViewBuilder
    private var receiptAttachButton: some View {
        #if canImport(UIKit)
        Button {
            vm.showingReceiptPicker = true
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "doc.viewfinder")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attach receipt photo")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Amount will be pre-filled from OCR")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer(minLength: BrandSpacing.sm)
                if vm.isOCRRunning {
                    ProgressView()
                        .accessibilityLabel("Reading receipt")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attach receipt photo. Amount will be pre-filled from OCR")
        .accessibilityIdentifier("expenses.attachReceipt")
        #else
        EmptyView()
        #endif
    }
}
