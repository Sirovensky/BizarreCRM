#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.7 — post-sale success card. Replaces the older
/// `PosChargePlaceholderSheet`. The view runs a brief `ProgressView`
/// spinner while `PosPostSaleViewModel.runSpinner()` resolves, then
/// transitions to a glass success card with Email / Text / Print / Next
/// sale actions.
///
/// Wiring:
/// - `Email receipt` posts to `/notifications/send-receipt`; while §17.3
///   is pending the server 400s on `invoice_id: -1` — the view model
///   treats that as soft success.
/// - `Text receipt` posts to `/sms/send` with the rendered text body.
/// - `Print` stays disabled with a tooltip until §17.4 wires a driver.
/// - `Next sale` dismisses the sheet after firing the host's cart-clear.
struct PosPostSaleView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: PosPostSaleViewModel
    @State private var showingReceiptSummary = false

    // §16.8 — Auto-dismiss after 10 s when cashier does not interact.
    @State private var autoDismissCountdown: Int = 10
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var userInteracted: Bool = false

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            switch vm.phase {
            case .processing:
                processingContent
            case .completed:
                completedContent
            }
        }
        .task { await vm.runSpinner() }
        // §16.8 — Start auto-dismiss countdown once completed phase lands.
        .onChange(of: vm.phase) { _, newPhase in
            if newPhase == .completed {
                startAutoDismissCountdown()
            }
        }
        // §16.8 — Any sheet interaction cancels auto-dismiss.
        .onChange(of: vm.activeSheet) { _, _ in cancelAutoDismiss() }
        .onChange(of: showingReceiptSummary) { _, _ in cancelAutoDismiss() }
        .sheet(item: Binding(
            get: { vm.activeSheet },
            set: { vm.activeSheet = $0 }
        )) { sheet in
            switch sheet {
            case .email:
                PosReceiptEmailSheet(vm: vm)
            case .sms:
                PosReceiptTextSheet(vm: vm)
            }
        }
        .sheet(isPresented: $showingReceiptSummary) {
            if let payload = vm.receiptPayload {
                PosReceiptSummaryView(payload: payload)
            }
        }
    }

    // MARK: - §16.8 Auto-dismiss

    private func startAutoDismissCountdown() {
        guard !userInteracted else { return }
        autoDismissCountdown = 10
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor in
            while autoDismissCountdown > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                autoDismissCountdown -= 1
            }
            guard !Task.isCancelled, !userInteracted else { return }
            BrandHaptics.lightImpact()
            vm.triggerNextSale()
            dismiss()
        }
    }

    private func cancelAutoDismiss() {
        userInteracted = true
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }

    private var processingContent: some View {
        VStack(spacing: BrandSpacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("pos.postSale.spinner")
            Text("Charging \(CartMath.formatCents(vm.totalCents))…")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completedContent: some View {
        VStack(spacing: 0) {
            Spacer()
            successCard
                .padding(.horizontal, BrandSpacing.base)
            Spacer()
            actionButtons
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.lg)
        }
        .accessibilityIdentifier("pos.postSale.completed")
    }

    /// Glass success block. Reads as chrome over the dark base so the
    /// checkmark lands as the first thing a cashier's eye parses.
    private var successCard: some View {
        VStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.bizarreSuccess.opacity(0.15))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.bizarreSuccess)
            }
            .accessibilityHidden(true)

            Text("\(CartMath.formatCents(vm.totalCents)) charged")
                .font(.brandHeadlineLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityIdentifier("pos.postSale.amount")

            Text(vm.methodLabel)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, BrandSpacing.xl)
        .padding(.horizontal, BrandSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 24))
    }

    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let banner = vm.emailStatus.bannerText ?? vm.smsStatus.bannerText {
                Text(banner)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, BrandSpacing.sm)
                    .accessibilityIdentifier("pos.postSale.banner")
            }

            HStack(spacing: BrandSpacing.sm) {
                receiptActionButton(
                    label: "Email",
                    system: "envelope",
                    identifier: "pos.postSale.emailButton"
                ) { vm.openEmailSheet() }
                receiptActionButton(
                    label: "Text",
                    system: "message",
                    identifier: "pos.postSale.textButton"
                ) { vm.openSmsSheet() }
                receiptActionButton(
                    label: "Print",
                    system: "printer",
                    identifier: "pos.postSale.printButton",
                    disabled: true,
                    tooltip: "Printing lands in §17.4"
                ) { }
            }

            if vm.receiptPayload != nil {
                Button {
                    showingReceiptSummary = true
                } label: {
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: "doc.text")
                        Text("View receipt")
                            .font(.brandBodyMedium())
                    }
                    .foregroundStyle(.bizarreOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("pos.postSale.viewReceipt")
            }

            Button {
                BrandHaptics.success()
                vm.triggerNextSale()
                dismiss()
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "arrow.forward.circle.fill")
                    Text("Next sale")
                        .font(.brandTitleMedium())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("pos.postSale.nextSale")
            .simultaneousGesture(TapGesture().onEnded { cancelAutoDismiss() })

            // §16.8 — Auto-dismiss countdown label
            if !userInteracted, autoDismissCountdown > 0, autoDismissCountdown < 10 {
                Text("Starting new sale in \(autoDismissCountdown)s…")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pos.postSale.autoDismissLabel")
                    .onTapGesture { cancelAutoDismiss() }
            }
        }
    }

    private func receiptActionButton(
        label: String,
        system: String,
        identifier: String,
        disabled: Bool = false,
        tooltip: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: system)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(.brandLabelLarge())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .foregroundStyle(disabled ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
        }
        .buttonStyle(.bordered)
        .tint(disabled ? .bizarreOnSurfaceMuted : .bizarreOrange)
        .disabled(disabled)
        .help(tooltip ?? "")
        .accessibilityIdentifier(identifier)
        .accessibilityHint(tooltip ?? "")
    }
}

private extension PosPostSaleViewModel.SendStatus {
    /// Text for the single status banner above the action row. Returns
    /// `nil` when idle or mid-flight — callers should surface the spinner
    /// separately inside the respective sheet.
    var bannerText: String? {
        switch self {
        case .idle, .sending: return nil
        case .sent(let msg):   return msg
        case .failed(let msg): return msg
        }
    }
}
#endif
