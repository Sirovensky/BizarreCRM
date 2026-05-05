#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem
import Networking

/// §41 — cart-level "Send payment link" sheet. Two-step layout:
///   1. **Editing**: pre-filled amount / email / phone / description /
///      expiry picker. Primary CTA creates the link.
///   2. **Ready / Paid**: renders the pay URL, Copy + Share buttons, and
///      a "Waiting for payment" pill. The sheet stays open while the
///      view-model polls; on `status == "paid"` it flips to the success
///      card and auto-dismisses after 3 s.
public struct PosPaymentLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PosPaymentLinkViewModel
    @State private var showingShare: Bool = false
    @State private var showCopiedToast: Bool = false

    /// Fires as soon as the create call succeeds. POS wires this to
    /// `cart.markPendingPaymentLink(...)` so Charge stays disabled while
    /// the customer is paying via the web page.
    public let onLinkCreated: (PaymentLink) -> Void
    /// Fires when the status poll observes `paid` — POS clears the
    /// pending marker and resets the cart.
    public let onPaid: (PaymentLink) -> Void

    public init(
        api: APIClient,
        amountCents: Int,
        customerEmail: String = "",
        customerPhone: String = "",
        customerId: Int64? = nil,
        description: String = "Invoice from BizarreCRM",
        onLinkCreated: @escaping (PaymentLink) -> Void,
        onPaid: @escaping (PaymentLink) -> Void
    ) {
        _vm = State(wrappedValue: PosPaymentLinkViewModel(
            api: api,
            amountCents: amountCents,
            customerEmail: customerEmail,
            customerPhone: customerPhone,
            customerId: customerId,
            description: description
        ))
        self.onLinkCreated = onLinkCreated
        self.onPaid = onPaid
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Send payment link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast { copiedToast }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear { vm.cancelPolling() }
        .onChange(of: vm.phase) { _, new in
            switch new {
            case .ready(let link):
                onLinkCreated(link)
                BrandHaptics.success()
            case .paid(let link):
                onPaid(link)
                BrandHaptics.success()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    dismiss()
                }
            default:
                break
            }
        }
    }

    private func close() {
        vm.cancelPolling()
        dismiss()
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .editing, .creating: PosPaymentLinkFormView(vm: vm, onCreate: createAction)
        case .ready(let link):    readyCard(link: link, paid: false)
        case .paid(let link):     readyCard(link: link, paid: true)
        }
    }

    private func createAction() {
        BrandHaptics.tapMedium()
        Task { await vm.create() }
    }

    // MARK: - Ready / Paid card

    private func readyCard(link: PaymentLink, paid: Bool) -> some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                PosPaymentLinkStatusBadge(paid: paid, amountCents: vm.amountCents)
                PosPaymentLinkURLCard(link: link)
                if !paid {
                    actionRow(link: link)
                    waitingPill
                } else {
                    paidHint
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.lg)
        }
    }

    private func actionRow(link: PaymentLink) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Button {
                BrandHaptics.tap()
                UIPasteboard.general.string = link.url
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
            .accessibilityIdentifier("pos.paymentLink.copyButton")

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
            .accessibilityIdentifier("pos.paymentLink.shareButton")
        }
        .controlSize(.large)
        .sheet(isPresented: $showingShare) {
            PosShareSheet(items: [link.url])
        }
    }

    private var waitingPill: some View {
        HStack(spacing: BrandSpacing.sm) {
            ProgressView()
            Text("Waiting for payment…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private var paidHint: some View {
        Text("This sheet will close automatically.")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .multilineTextAlignment(.center)
            .padding(.vertical, BrandSpacing.md)
    }

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

/// Editing form — pulled out of `PosPaymentLinkSheet` so the parent view
/// stays focused on the phase switch + success chrome.
struct PosPaymentLinkFormView: View {
    @Bindable var vm: PosPaymentLinkViewModel
    let onCreate: () -> Void

    var body: some View {
        Form {
            Section("Amount") {
                HStack {
                    Text("Total")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(CartMath.formatCents(vm.amountCents))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            Section("Customer") {
                TextField("Email (optional)", text: $vm.customerEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Phone (optional)", text: $vm.customerPhone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }
            Section("Memo") {
                TextField("Description", text: $vm.description, axis: .vertical)
                    .lineLimit(1...3)
            }
            Section {
                Picker("Expires in", selection: $vm.expiryDays) {
                    Text("1 day").tag(1)
                    Text("3 days").tag(3)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Expiry")
            } footer: {
                Text("Customer can pay any time before the link expires.")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let msg = vm.errorMessage {
                Section {
                    Text(msg)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("pos.paymentLink.error")
                }
            }
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
                .disabled(!canCreate)
                .accessibilityIdentifier("pos.paymentLink.createButton")
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var canCreate: Bool {
        guard vm.amountCents > 0 else { return false }
        if case .creating = vm.phase { return false }
        return true
    }

    private var createLabel: String {
        if case .creating = vm.phase { return "Creating..." }
        return "Create link for \(CartMath.formatCents(vm.amountCents))"
    }
}

/// Status banner on the ready / paid card.
struct PosPaymentLinkStatusBadge: View {
    let paid: Bool
    let amountCents: Int

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: paid ? "checkmark.seal.fill" : "link")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(paid ? Color.green : Color.bizarreOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(paid ? "Payment received" : "Link is live")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(CartMath.formatCents(amountCents))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Read-only card showing the share URL with text-selection enabled.
struct PosPaymentLinkURLCard: View {
    let link: PaymentLink

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Pay URL")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(link.url.isEmpty ? "(pending)" : link.url)
                .font(.brandMono(size: 13))
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .textSelection(.enabled)
                .accessibilityIdentifier("pos.paymentLink.url")
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Thin `UIActivityViewController` wrapper for the Share button.
struct PosShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
