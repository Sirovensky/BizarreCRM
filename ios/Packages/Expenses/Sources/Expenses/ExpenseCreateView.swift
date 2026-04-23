import SwiftUI
import Observation
import PhotosUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import Camera
import UIKit
#endif

// MARK: - ViewModel

@MainActor
@Observable
public final class ExpenseCreateViewModel {
    // MARK: Form fields
    public var category: String = ""
    public var amountText: String = ""
    public var vendor: String = ""
    public var taxAmountText: String = ""
    public var paymentMethod: String = ""
    public var descriptionText: String = ""
    public var notes: String = ""
    public var date: Date = Date()
    public var isReimbursable: Bool = false

    // MARK: State
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?
    /// `true` while OCR is running.
    public private(set) var isOCRRunning: Bool = false
    /// Controls the camera receipt picker sheet.
    public var showingCameraReceiptPicker: Bool = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

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

    // MARK: - OCR from camera / photo library

#if canImport(UIKit)
    @MainActor
    public func handleCapturedImages(_ images: [UIImage]) async {
        showingCameraReceiptPicker = false
        guard let first = images.first else { return }
        isOCRRunning = true
        defer { isOCRRunning = false }
        if let total = await ReceiptEdgeDetector.ocrTotal(first) {
            let formatted = String(format: "%.2f", total)
            if amountText.isEmpty || (Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) == 0 {
                amountText = formatted
            }
        }
    }
#endif

    /// Called after user picks a photo from library (`PhotosPickerItem`).
    /// OCR runs only on UIKit (iOS); on macOS the data load is a no-op.
    @MainActor
    public func handlePhotoLibraryItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isOCRRunning = true
        defer { isOCRRunning = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        #if canImport(UIKit)
        guard let img = UIImage(data: data) else { return }
        if let total = await ReceiptEdgeDetector.ocrTotal(img) {
            let formatted = String(format: "%.2f", total)
            if amountText.isEmpty || (Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0) == 0 {
                amountText = formatted
            }
        }
        #endif
    }

    // MARK: - Submit

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

        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPayment = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)

        let req = CreateExpenseRequest(
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
            let created = try await api.createExpense(req)
            createdId = created.id
        } catch {
            AppLog.ui.error("Expense create failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct ExpenseCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ExpenseCreateViewModel
    @State private var photoLibraryItem: PhotosPickerItem?

    public init(api: APIClient) { _vm = State(wrappedValue: ExpenseCreateViewModel(api: api)) }

    public var body: some View {
        NavigationStack {
            formContent
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
                .navigationTitle("New Expense")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarItems }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $vm.showingCameraReceiptPicker) {
            PhotoCaptureView { images in
                Task { await vm.handleCapturedImages(images) }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
        .onChange(of: photoLibraryItem) { _, newItem in
            Task { await vm.handlePhotoLibraryItem(newItem) }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        Form {
            amountSection
            categorySection
            vendorPaymentSection
            dateReimbursableSection
            notesSection
            receiptSection
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
                    .accessibilityLabel("Tax amount in US dollars")
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

    @ViewBuilder
    private var receiptSection: some View {
        Section("Receipt") {
            #if canImport(UIKit)
            Button {
                vm.showingCameraReceiptPicker = true
            } label: {
                receiptButtonLabel(
                    systemImage: "camera.fill",
                    title: "Take photo",
                    subtitle: "Capture receipt now"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take photo of receipt with camera")
            .accessibilityIdentifier("expenses.camera")

            PhotosPicker(
                selection: $photoLibraryItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                receiptButtonLabel(
                    systemImage: "photo.on.rectangle",
                    title: "Photo library",
                    subtitle: "Pick existing receipt photo"
                )
            }
            .accessibilityLabel("Import receipt from photo library")
            .accessibilityIdentifier("expenses.photoLibrary")

            if vm.isOCRRunning {
                HStack(spacing: BrandSpacing.sm) {
                    ProgressView()
                        .accessibilityLabel("Reading receipt amount")
                    Text("Reading receipt…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            #else
            Text("Receipt capture not available on this platform.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            #endif
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private func receiptButtonLabel(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.bizarreOrange)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(subtitle)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: BrandSpacing.sm)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("expenses.create.cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            if vm.isOCRRunning {
                ProgressView()
                    .accessibilityLabel("Processing receipt")
            } else {
                Button(vm.isSubmitting ? "Saving…" : "Save") {
                    Task {
                        await vm.submit()
                        if vm.createdId != nil { dismiss() }
                    }
                }
                .disabled(!vm.isValid || vm.isSubmitting)
                .accessibilityIdentifier("expenses.create.save")
            }
        }
    }
}
