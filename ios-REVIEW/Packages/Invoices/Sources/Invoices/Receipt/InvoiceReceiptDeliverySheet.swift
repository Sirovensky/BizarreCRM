#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.4 Post-payment receipt delivery sheet.
//
// Shown after a successful payment is recorded. Offers four options:
//   1. AirPrint     — renders PDF via InvoicePrintService, hands to UIPrintInteractionController.
//   2. Email        — sends via POST /invoices/:id/email-receipt.
//   3. SMS          — sends via POST /sms/send (pre-filled with payment total).
//   4. PDF download — renders PDF, presents ShareLink / .fileExporter.
//
// iPhone: bottom sheet (.medium / .large detents).
// iPad: popover-style .large detent, max 520pt wide.

// MARK: - ViewModel

@MainActor
@Observable
public final class InvoiceReceiptDeliveryViewModel {

    public enum DeliveryMethod: String, CaseIterable, Sendable, Identifiable {
        case airPrint = "airPrint"
        case email    = "email"
        case sms      = "sms"
        case pdf      = "pdf"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .airPrint: return "Print"
            case .email:    return "Email"
            case .sms:      return "SMS"
            case .pdf:      return "Save PDF"
            }
        }

        public var systemImage: String {
            switch self {
            case .airPrint: return "printer"
            case .email:    return "envelope"
            case .sms:      return "message"
            case .pdf:      return "arrow.down.doc"
            }
        }
    }

    public enum State: Sendable, Equatable {
        case idle
        case generatingPDF
        case sending
        case success(String)
        case failed(String)
    }

    // MARK: - Inputs
    public var emailAddress: String = ""
    public var phone: String = ""

    // MARK: - Invoice context
    public let invoiceId: Int64
    public let invoiceNumber: String
    public let customerEmail: String?
    public let customerPhone: String?
    /// Payment total in cents for SMS pre-fill.
    public let paymentCents: Int

    // MARK: - State
    public private(set) var state: State = .idle
    public private(set) var pdfURL: URL?

    @ObservationIgnored private let repository: InvoiceReceiptDeliveryRepository
    @ObservationIgnored private let printService: InvoicePrintService

    public init(
        invoiceId: Int64,
        invoiceNumber: String,
        customerEmail: String?,
        customerPhone: String?,
        paymentCents: Int,
        repository: InvoiceReceiptDeliveryRepository,
        printService: InvoicePrintService = InvoicePrintService()
    ) {
        self.invoiceId = invoiceId
        self.invoiceNumber = invoiceNumber
        self.customerEmail = customerEmail
        self.customerPhone = customerPhone
        self.paymentCents = paymentCents
        self.repository = repository
        self.printService = printService
        self.emailAddress = customerEmail ?? ""
        self.phone = customerPhone ?? ""
    }

    // MARK: - Actions

    /// Generate PDF for AirPrint or download. Caller reads `pdfURL` after success.
    @discardableResult
    public func generatePDF(invoice: InvoiceDetail) async -> URL? {
        guard case .idle = state else { return pdfURL }
        state = .generatingPDF
        do {
            let url = try await printService.generatePDF(invoice: invoice)
            pdfURL = url
            state = .idle
            return url
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Send email receipt via repository (POST /api/v1/invoices/:id/email-receipt).
    public func sendEmail() async {
        let email = emailAddress.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else {
            state = .failed("Please enter an email address.")
            return
        }
        state = .sending
        do {
            try await repository.emailReceipt(invoiceId: invoiceId, email: email)
            state = .success("Receipt emailed to \(email).")
        } catch {
            state = .failed("Email failed: \(error.localizedDescription)")
        }
    }

    /// Send SMS receipt via repository (POST /api/v1/sms/send).
    public func sendSMS() async {
        let cleaned = phone.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else {
            state = .failed("Please enter a phone number.")
            return
        }
        state = .sending
        do {
            let totalStr = formatCents(paymentCents)
            let message = "Payment of \(totalStr) received for \(invoiceNumber). Thank you!"
            try await repository.smsReceipt(phone: cleaned, message: message)
            state = .success("Receipt sent to \(cleaned).")
        } catch {
            state = .failed("SMS failed: \(error.localizedDescription)")
        }
    }

    public func resetToIdle() { state = .idle }

    // MARK: - Helpers
    private func formatCents(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents)"
    }
}

// MARK: - View

public struct InvoiceReceiptDeliverySheet: View {
    @State private var vm: InvoiceReceiptDeliveryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The full invoice detail — needed for PDF generation.
    public let invoice: InvoiceDetail?
    public let onDone: () -> Void

    public init(
        vm: InvoiceReceiptDeliveryViewModel,
        invoice: InvoiceDetail?,
        onDone: @escaping () -> Void
    ) {
        _vm = State(wrappedValue: vm)
        self.invoice = invoice
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.md) {
                        headerCard
                        methodGrid
                        contactSection
                        sendButton
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Send Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onDone()
                        dismiss()
                    }
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Skip sending receipt")
                }
            }
            .toolbarBackground(.bizarreSurface1, for: .navigationBar)
            .sheet(item: airPrintURL) { url in
                AirPrintSheet(url: url.url)
            }
            .sheet(isPresented: showPDFExporter) {
                if let url = vm.pdfURL {
                    ReceiptShareSheet(items: [url])
                }
            }
            .alert("Receipt Error", isPresented: failedBinding) {
                Button("OK") { vm.resetToIdle() }
            } message: {
                if case let .failed(msg) = vm.state { Text(msg) }
            }
            .onChange(of: vm.state) { _, newState in
                if case let .success(msg) = newState {
                    _ = msg // message shown in success card
                }
            }
        }
        .frame(maxWidth: Platform.isCompact ? .infinity : 520)
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: BrandSpacing.xxs) {
            if case let .success(msg) = vm.state {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreSuccess)
                    .multilineTextAlignment(.center)
                Button("Done") {
                    onDone()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.bizarreOrange)
                .font(.brandTitleMedium())
                .padding(.top, BrandSpacing.sm)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text("Payment recorded")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("How would you like to send the receipt?")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Method selector

    @State private var selectedMethod: InvoiceReceiptDeliveryViewModel.DeliveryMethod = .email

    private var methodGrid: some View {
        HStack(spacing: BrandSpacing.sm) {
            ForEach(InvoiceReceiptDeliveryViewModel.DeliveryMethod.allCases) { method in
                methodTile(method)
            }
        }
        .accessibilityLabel("Select receipt delivery method")
    }

    private func methodTile(_ method: InvoiceReceiptDeliveryViewModel.DeliveryMethod) -> some View {
        Button {
            selectedMethod = method
        } label: {
            VStack(spacing: BrandSpacing.xxs) {
                Image(systemName: method.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(selectedMethod == method ? .white : .bizarreOrange)
                    .accessibilityHidden(true)
                Text(method.title)
                    .font(.brandLabelSmall())
                    .foregroundStyle(selectedMethod == method ? .white : .bizarreOnSurface)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .background(
                selectedMethod == method ? Color.bizarreOrange : Color.bizarreSurface2,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            )
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: DesignTokens.Motion.quick),
                   value: selectedMethod)
        .accessibilityLabel(method.title)
        .accessibilityAddTraits(selectedMethod == method ? [.isSelected] : [])
    }

    // MARK: - Contact fields

    @ViewBuilder
    private var contactSection: some View {
        switch selectedMethod {
        case .email:
            contactField(label: "Email address",
                         prompt: "customer@example.com",
                         text: $vm.emailAddress,
                         keyboardType: .emailAddress,
                         contentType: .emailAddress)
        case .sms:
            contactField(label: "Phone number",
                         prompt: "+1 555 000 0000",
                         text: $vm.phone,
                         keyboardType: .phonePad,
                         contentType: .telephoneNumber)
        case .airPrint, .pdf:
            EmptyView()
        }
    }

    private func contactField(
        label: String,
        prompt: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType,
        contentType: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            TextField(prompt, text: text)
                .keyboardType(keyboardType)
                .textContentType(contentType)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .accessibilityLabel(label)
        }
    }

    // MARK: - Send button

    @State private var airPrintTrigger: IdentifiableURL? = nil
    @State private var showPDFShare = false

    private var sendButton: some View {
        Button {
            Task { await handleSend() }
        } label: {
            Group {
                if vm.state == .generatingPDF || vm.state == .sending {
                    ProgressView().tint(.white)
                } else {
                    Text(sendLabel)
                        .font(.brandTitleMedium())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .brandGlass(.regular,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                    tint: .bizarreOrange,
                    interactive: true)
        .foregroundStyle(.white)
        .disabled(isButtonDisabled)
        .animation(reduceMotion ? .none : .spring(response: DesignTokens.Motion.snappy),
                   value: isButtonDisabled)
        .accessibilityLabel(sendLabel)
    }

    private var sendLabel: String {
        switch selectedMethod {
        case .airPrint: return "Print"
        case .email:    return "Email Receipt"
        case .sms:      return "Send SMS"
        case .pdf:      return "Save PDF"
        }
    }

    private var isButtonDisabled: Bool {
        vm.state == .generatingPDF || vm.state == .sending
    }

    // MARK: - Action handler

    private func handleSend() async {
        switch selectedMethod {
        case .email:
            await vm.sendEmail()
        case .sms:
            await vm.sendSMS()
        case .airPrint:
            guard let inv = invoice else {
                vm.resetToIdle()
                return
            }
            if let url = await vm.generatePDF(invoice: inv) {
                airPrintTrigger = IdentifiableURL(url: url)
            }
        case .pdf:
            guard let inv = invoice else {
                vm.resetToIdle()
                return
            }
            if await vm.generatePDF(invoice: inv) != nil {
                showPDFShare = true
            }
        }
    }

    // MARK: - Sheet bindings

    private var airPrintURL: Binding<IdentifiableURL?> {
        Binding(get: { airPrintTrigger }, set: { airPrintTrigger = $0 })
    }

    private var showPDFExporter: Binding<Bool> {
        Binding(get: { showPDFShare }, set: { showPDFShare = $0 })
    }

    private var failedBinding: Binding<Bool> {
        .constant({
            if case .failed = vm.state { return true }
            return false
        }())
    }
}

// MARK: - AirPrint sheet wrapper

private struct AirPrintSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.async {
            let printInfo = UIPrintInfo(dictionary: nil)
            printInfo.outputType = .general
            printInfo.jobName = url.lastPathComponent
            let controller = UIPrintInteractionController.shared
            controller.printInfo = printInfo
            controller.printingItem = url
            controller.present(animated: true, completionHandler: nil)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - Local share sheet

private struct ReceiptShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Identifiable URL helper

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

#endif
