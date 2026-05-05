#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem
import Networking

// MARK: - §41 Standalone Payment Link Create Sheet

/// Standalone sheet for creating a payment link outside the POS cart flow —
/// e.g. from Operations menu, the standalone `PaymentLinksListView` FAB, or
/// deep-linked from an invoice detail.
///
/// Distinct from `PosPaymentLinkSheet` (which is cart-embedded and pre-fills
/// the cart total). This sheet accepts an optional invoice ID for linking and
/// a free-form amount entry.
///
/// On success the caller receives a fully-hydrated `PaymentLink` via
/// `onCreated`. The sheet then transitions to the ready card showing the QR +
/// URL + Copy/Share; it does NOT begin polling for paid status — that is
/// delegated to `PaymentLinkDetailView` if the caller navigates there.
public struct PaymentLinkCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PaymentLinkCreateViewModel
    @State private var showingShare: Bool = false
    @State private var showCopiedToast: Bool = false

    /// Fired once when the link is successfully created.
    public let onCreated: (PaymentLink) -> Void

    public init(
        api: APIClient,
        invoiceId: Int64? = nil,
        customerId: Int64? = nil,
        prefillAmountCents: Int = 0,
        onCreated: @escaping (PaymentLink) -> Void
    ) {
        _vm = State(wrappedValue: PaymentLinkCreateViewModel(
            api: api,
            invoiceId: invoiceId,
            customerId: customerId,
            prefillAmountCents: prefillAmountCents
        ))
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("paymentLinks.create.closeButton")
                }
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast { copiedToast }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: vm.createdLink) { _, link in
            guard let link else { return }
            onCreated(link)
            BrandHaptics.success()
        }
    }

    private var navTitle: String {
        switch vm.phase {
        case .editing, .creating: return "New payment link"
        case .ready: return "Link ready"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .editing, .creating:
            PaymentLinkCreateForm(vm: vm) {
                BrandHaptics.tapMedium()
                Task { await vm.create() }
            }
        case .ready(let link):
            readyCard(link: link)
        }
    }

    // MARK: - Ready card

    private func readyCard(link: PaymentLink) -> some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                readyBadge
                qrView(url: link.url)
                urlCard(link: link)
                actionRow(link: link)
                openDetailButton(link: link)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.lg)
        }
    }

    private var readyBadge: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.bizarreOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Link is live")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let link = vm.createdLink {
                    Text(CartMath.formatCents(link.amountCents))
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func qrView(url: String) -> some View {
        if url.isEmpty {
            Color.bizarreSurface1
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { ProgressView() }
        } else if let img = BrandedQRGenerator.generate(urlString: url, size: 200) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                .accessibilityLabel("QR code for payment link")
        }
    }

    private func urlCard(link: PaymentLink) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Pay URL")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(link.url.isEmpty ? "(building URL…)" : link.url)
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .textSelection(.enabled)
                .accessibilityIdentifier("paymentLinks.create.url")
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionRow(link: PaymentLink) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Button {
                UIPasteboard.general.string = link.url
                BrandHaptics.tap()
                showCopiedToast = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    showCopiedToast = false
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.bizarreOrange)
            .disabled(link.url.isEmpty)
            .accessibilityIdentifier("paymentLinks.create.copyButton")

            Button {
                BrandHaptics.tap()
                showingShare = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(link.url.isEmpty)
            .accessibilityIdentifier("paymentLinks.create.shareButton")
        }
        .controlSize(.large)
        .sheet(isPresented: $showingShare) {
            PosShareSheet(items: [link.url])
        }
    }

    private func openDetailButton(link: PaymentLink) -> some View {
        NavigationLink {
            PaymentLinkDetailView(link: link, api: vm.apiClient)
        } label: {
            Label("View details & QR", systemImage: "arrow.up.right.square")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .controlSize(.large)
        .accessibilityIdentifier("paymentLinks.create.openDetailButton")
    }

    // MARK: - Toast

    private var copiedToast: some View {
        Text("Copied to clipboard")
            .font(.brandLabelLarge())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.black.opacity(0.85), in: Capsule())
            .padding(.bottom, BrandSpacing.xl)
            .transition(.opacity)
    }
}

// MARK: - PaymentLinkCreateForm

/// The editable form portion of the create sheet.
struct PaymentLinkCreateForm: View {
    @Bindable var vm: PaymentLinkCreateViewModel
    let onCreate: () -> Void

    var body: some View {
        Form {
            amountSection
            invoiceSection
            descriptionSection
            expirySection
            errorSection
            createSection
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Amount

    private var amountSection: some View {
        Section("Amount") {
            HStack {
                Text("$")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                TextField("0.00", text: $vm.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("paymentLinks.create.amountField")
            }
            if let hint = vm.amountHint {
                Text(hint)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    // MARK: Invoice association (optional)

    @ViewBuilder
    private var invoiceSection: some View {
        Section {
            TextField("Invoice ID (optional)", text: $vm.invoiceIdText)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("paymentLinks.create.invoiceIdField")
        } header: {
            Text("Invoice association")
        } footer: {
            Text("Optionally link this payment to an existing invoice.")
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: Description

    private var descriptionSection: some View {
        Section("Memo") {
            TextField("Description (optional)", text: $vm.description, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("paymentLinks.create.descriptionField")
        }
    }

    // MARK: Expiry

    private var expirySection: some View {
        Section {
            Picker("Expires in", selection: $vm.expiryDays) {
                Text("1 day").tag(1)
                Text("3 days").tag(3)
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("paymentLinks.create.expiryPicker")
        } header: {
            Text("Expiry")
        } footer: {
            Text("Customer can pay any time before the link expires.")
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: Error

    @ViewBuilder
    private var errorSection: some View {
        if let msg = vm.errorMessage {
            Section {
                Text(msg)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("paymentLinks.create.error")
            }
        }
    }

    // MARK: Create button

    private var createSection: some View {
        Section {
            Button(action: onCreate) {
                HStack(spacing: BrandSpacing.sm) {
                    if case .creating = vm.phase { ProgressView() }
                    Text(createLabel)
                        .font(.brandTitleSmall())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .controlSize(.large)
            .disabled(!vm.canCreate)
            .accessibilityIdentifier("paymentLinks.create.createButton")
            .listRowBackground(Color.clear)
        }
    }

    private var createLabel: String {
        if case .creating = vm.phase { return "Creating..." }
        let cents = vm.parsedAmountCents
        if cents > 0 {
            return "Create link for \(CartMath.formatCents(cents))"
        }
        return "Create payment link"
    }
}

// MARK: - ViewModel

/// Observable view-model for `PaymentLinkCreateSheet`.
///
/// Handles free-form dollar amount entry (converted to cents for the API),
/// optional invoice ID binding, expiry picker, and the create network call.
@MainActor
@Observable
public final class PaymentLinkCreateViewModel {

    // MARK: - Inputs

    /// Dollar amount as typed by the user — keeps the text field editable.
    public var amountText: String
    /// Optional invoice ID as typed.
    public var invoiceIdText: String
    public var description: String
    public var expiryDays: Int

    // MARK: - Derived / output

    public enum Phase: Equatable, Sendable {
        case editing
        case creating
        case ready(PaymentLink)
    }

    public private(set) var phase: Phase = .editing
    public private(set) var errorMessage: String?

    /// Set as soon as the create call succeeds so `onChange` can fire `onCreated`.
    public private(set) var createdLink: PaymentLink?

    /// Expose the API client so the ready card can push `PaymentLinkDetailView`.
    public let apiClient: APIClient

    private let presetInvoiceId: Int64?
    private let presetCustomerId: Int64?

    public init(
        api: APIClient,
        invoiceId: Int64? = nil,
        customerId: Int64? = nil,
        prefillAmountCents: Int = 0
    ) {
        self.apiClient = api
        self.presetInvoiceId = invoiceId
        self.presetCustomerId = customerId
        // Pre-fill the text field if a cents value was passed in.
        if prefillAmountCents > 0 {
            let dollars = Double(prefillAmountCents) / 100.0
            self.amountText = String(format: "%.2f", dollars)
        } else {
            self.amountText = ""
        }
        // Populate invoice ID field from preset.
        self.invoiceIdText = invoiceId.map { String($0) } ?? ""
        self.description = ""
        self.expiryDays = 7
    }

    // MARK: - Validation

    /// Parse the amount text → cents. Returns 0 for invalid / empty input.
    public var parsedAmountCents: Int {
        guard let dollars = Double(amountText), dollars > 0 else { return 0 }
        // Mirror the server's toFixed(2) approach to avoid FP drift.
        // String(format:) on a finite Double always yields a parseable string.
        let fixedString = String(format: "%.2f", dollars)
        guard let fixedDollars = Double(fixedString) else { return 0 }
        return Int(round(fixedDollars * 100))
    }

    /// Human-readable hint shown below the amount field.
    public var amountHint: String? {
        let cents = parsedAmountCents
        if cents > 0 {
            return CartMath.formatCents(cents)
        }
        if !amountText.isEmpty {
            return "Enter a valid amount (e.g. 19.99)"
        }
        return nil
    }

    public var canCreate: Bool {
        guard parsedAmountCents > 0 else { return false }
        if case .creating = phase { return false }
        if case .ready = phase { return false }
        return true
    }

    // MARK: - Create

    public func create() async {
        guard canCreate else { return }

        phase = .creating
        errorMessage = nil

        let invoiceId: Int64? = {
            guard let id = Int64(invoiceIdText.trimmingCharacters(in: .whitespaces)), id > 0
            else { return presetInvoiceId }
            return id
        }()

        let request = CreatePaymentLinkRequest(
            amountCents: parsedAmountCents,
            customerId: presetCustomerId,
            description: description.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : description.trimmingCharacters(in: .whitespaces),
            expiresAt: PosPaymentLinkViewModel.expiryISO(daysFromNow: expiryDays),
            invoiceId: invoiceId
        )

        do {
            let link = try await apiClient.createPaymentLink(request)
            createdLink = link
            phase = .ready(link)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not create payment link. Please try again."
            phase = .editing
        }
    }
}
#endif
