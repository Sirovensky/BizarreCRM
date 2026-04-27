#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40.2 — Issue store credit on returns, apologies, or promos.
///
/// Manager/admin action. The credit amount is posted to
/// `POST /api/v1/refunds/credits/:customerId` (the same endpoint the refund
/// flow uses with `type: store_credit`).
///
/// Reason types:
///   - Return: tied to a specific invoice (shows invoice id).
///   - Apology: goodwill credit, no invoice required.
///   - Promo: promotional credit, optional notes.
///
/// Manager PIN required above `PosTenantLimits.storeCreditPinThresholdCents`
/// (default $25.00).
///
/// iPhone: `.large` sheet.
/// iPad: centred `.medium` sheet at 480 pt.
@MainActor
public struct IssuedStoreCreditSheet: View {

    // MARK: - Props

    let customerId: Int64
    let customerName: String
    let api: APIClient?
    /// Pre-fill when issuing after a return.
    let prefillAmountCents: Int?
    let prefillInvoiceId: Int64?
    let onIssued: ((Int) -> Void)?

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var vm: IssuedStoreCreditViewModel
    @State private var showManagerPin: Bool = false

    // MARK: - Init

    public init(
        customerId: Int64,
        customerName: String,
        api: APIClient?,
        prefillAmountCents: Int? = nil,
        prefillInvoiceId: Int64? = nil,
        onIssued: ((Int) -> Void)? = nil
    ) {
        self.customerId = customerId
        self.customerName = customerName
        self.api = api
        self.prefillAmountCents = prefillAmountCents
        self.prefillInvoiceId = prefillInvoiceId
        self.onIssued = onIssued
        _vm = State(wrappedValue: IssuedStoreCreditViewModel(
            customerId: customerId,
            api: api,
            prefillAmountCents: prefillAmountCents,
            prefillInvoiceId: prefillInvoiceId
        ))
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                recipientSection
                amountSection
                reasonSection
                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .accessibilityIdentifier("storeCredit.issue.error")
                    }
                }
                if case .issued(let amount) = vm.state {
                    successSection(amount: amount)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Issue Store Credit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .presentationDetents(Platform.isCompact ? [.large] : [.medium])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: Platform.isCompact ? nil : 480)
        .sheet(isPresented: $showManagerPin) {
            ManagerPinSheet(
                reason: "Store credit of \(CartMath.formatCents(vm.amountCents)) requires manager approval.",
                onApproved: { _ in
                    vm.managerApproved = true
                    Task { await vm.issue() }
                },
                onCancelled: { }
            )
        }
        .onChange(of: vm.state) { _, new in
            if case .issued(let amount) = new {
                onIssued?(amount)
            }
        }
    }

    // MARK: - Sections

    private var recipientSection: some View {
        Section("Recipient") {
            LabeledContent("Customer", value: customerName)
                .accessibilityIdentifier("storeCredit.issue.customer")
            if let invoiceId = prefillInvoiceId {
                LabeledContent("Invoice", value: "#\(invoiceId)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityIdentifier("storeCredit.issue.invoiceId")
            }
        }
    }

    private var amountSection: some View {
        Section("Amount") {
            HStack(spacing: BrandSpacing.sm) {
                Text("$")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $vm.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel("Credit amount in dollars")
                    .accessibilityIdentifier("storeCredit.issue.amount")
            }
            if vm.requiresManagerPin {
                Label("Manager PIN required for credits above \(CartMath.formatCents(vm.pinThresholdCents)).",
                      systemImage: "lock.shield.fill")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityIdentifier("storeCredit.issue.pinWarning")
            }
        }
    }

    private var reasonSection: some View {
        Section("Reason") {
            Picker("Category", selection: $vm.reasonCategory) {
                ForEach(IssuedStoreCreditViewModel.ReasonCategory.allCases) { cat in
                    Text(cat.label).tag(cat)
                }
            }
            .accessibilityIdentifier("storeCredit.issue.category")
            TextField("Notes (optional)", text: $vm.notes, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityIdentifier("storeCredit.issue.notes")
        }
    }

    private func successSection(amount: Int) -> some View {
        Section {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.bizarreSuccess)
                Text("\(CartMath.formatCents(amount)) credited to \(customerName)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
                Button("Done") { dismiss() }
                    .padding(.top, BrandSpacing.xs)
                    .accessibilityIdentifier("storeCredit.issue.done")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Success. \(CartMath.formatCents(amount)) store credit issued to \(customerName).")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if case .issuing = vm.state {
                ProgressView()
            } else if case .issued = vm.state {
                EmptyView()
            } else {
                Button("Issue") {
                    if vm.requiresManagerPin && !vm.managerApproved {
                        showManagerPin = true
                    } else {
                        Task { await vm.issue() }
                    }
                }
                .disabled(!vm.canIssue)
                .fontWeight(.semibold)
                .accessibilityIdentifier("storeCredit.issue.cta")
            }
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class IssuedStoreCreditViewModel {

    // MARK: - Types

    enum State: Equatable, Sendable {
        case idle
        case issuing
        case issued(Int)    // amountCents
        case failed
    }

    enum ReasonCategory: String, CaseIterable, Identifiable, Sendable {
        case returnRefund = "return"
        case apology = "apology"
        case promo = "promo"
        case adjustment = "adjustment"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .returnRefund: return "Return"
            case .apology:      return "Apology / goodwill"
            case .promo:        return "Promotion"
            case .adjustment:   return "Adjustment"
            }
        }
        var wireValue: String { rawValue }
    }

    // MARK: - Properties

    var amountText: String
    var notes: String = ""
    var reasonCategory: ReasonCategory = .returnRefund
    var state: State = .idle
    var errorMessage: String?
    var managerApproved: Bool = false

    let pinThresholdCents: Int = 2_500  // $25.00

    @ObservationIgnored let customerId: Int64
    @ObservationIgnored let api: APIClient?
    @ObservationIgnored let prefillInvoiceId: Int64?

    init(customerId: Int64, api: APIClient?, prefillAmountCents: Int?, prefillInvoiceId: Int64?) {
        self.customerId = customerId
        self.api = api
        self.prefillInvoiceId = prefillInvoiceId
        if let cents = prefillAmountCents, cents > 0 {
            let dollars = Decimal(cents) / 100
            amountText = "\(dollars)"
        } else {
            amountText = ""
        }
    }

    var amountCents: Int {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(".") {
            guard let v = Double(trimmed), v >= 0 else { return 0 }
            return Int((v * 100).rounded())
        } else {
            guard let v = Int(trimmed), v >= 0 else { return 0 }
            return v * 100
        }
    }

    var requiresManagerPin: Bool { amountCents > pinThresholdCents }

    var canIssue: Bool {
        guard case .issuing = state else {
            return amountCents > 0
        }
        return false
    }

    // MARK: - Action

    func issue() async {
        guard canIssue, let api else {
            errorMessage = api == nil ? "Server not connected." : "Enter an amount."
            return
        }
        state = .issuing
        errorMessage = nil

        let reason = "\(reasonCategory.label)\(notes.isEmpty ? "" : " · \(notes)")"
        let request = CustomerCreditRefundRequest(
            amountCents: amountCents,
            reason: reason,
            sourceInvoiceId: prefillInvoiceId
        )
        do {
            _ = try await api.refundCustomerCredit(customerId: customerId, request: request)
            AppLog.pos.info("Store credit issued: customerId=\(customerId) amount=\(amountCents)c reason=\(reason, privacy: .public)")
            BrandHaptics.success()
            state = .issued(amountCents)
        } catch let APITransportError.httpStatus(code, message) {
            state = .failed
            errorMessage = "Server error \(code): \(message ?? "please try again")"
        } catch {
            state = .failed
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview("Issue store credit — return") {
    IssuedStoreCreditSheet(
        customerId: 42,
        customerName: "Jane Doe",
        api: nil,
        prefillAmountCents: 3500,
        prefillInvoiceId: 1001
    )
    .preferredColorScheme(.dark)
}

#Preview("Issue store credit — apology") {
    IssuedStoreCreditSheet(
        customerId: 7,
        customerName: "Bob Smith",
        api: nil
    )
    .preferredColorScheme(.dark)
}
#endif
