#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

/// §Agent-E — Receipt confirmation screen. Shown immediately after a tender
/// settles. Replaces (sits alongside) `PosPostSaleView` — the older view is
/// retained for the spinner/phase transition; this view is the settled state.
///
/// Layout (iPhone + iPad share the same scroll body; iPad gets the collapse
/// modifier on the cart column via the parent):
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │  SUCCESS HERO  (check glyph + amount)   │
/// ├─────────────────────────────────────────┤
/// │  SHARE 4-UP GRID (Text / Email / Print / AirDrop)│
/// ├─────────────────────────────────────────┤
/// │  LOYALTY CELEBRATION ROW (if pts > 0)   │
/// ├─────────────────────────────────────────┤
/// │  RECEIPT PREVIEW (monospace, scrollable)│
/// ├─────────────────────────────────────────┤
/// │  POST-SALE ACTION ROW                   │
/// └─────────────────────────────────────────┘
/// ```
///
/// Haptic: `.sensoryFeedback(.success, trigger: paidAt)` fires once on appear.
///
/// Accessibility: dynamic type is capped at `.accessibility2` for the hero
/// amount — beyond that the layout breaks and the cashier needs to read the
/// figure clearly at a glance.
@MainActor
public struct PosReceiptView: View {

    @Bindable var vm: PosReceiptViewModel

    /// Optional pre-rendered receipt text from `PosReceiptRenderer`. Used by
    /// the preview block and the share sheet. Pass `nil` to hide the preview.
    public let receiptText: String?

    /// Trigger for the success haptic. Set to `Date()` from the parent when
    /// the transaction settles.
    public let paidAt: Date

    @State private var showReceiptPreview: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(
        vm: PosReceiptViewModel,
        receiptText: String? = nil,
        paidAt: Date = Date()
    ) {
        self.vm = vm
        self.receiptText = receiptText
        self.paidAt = paidAt
    }

    @Environment(\.horizontalSizeClass) private var hSizeClass

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if hSizeClass == .regular {
                iPadBody
            } else {
                scrollBody
            }
        }
        .sensoryFeedback(.success, trigger: paidAt)
        .sheet(isPresented: $showReceiptPreview) {
            receiptPreviewSheet
        }
        .accessibilityIdentifier("pos.receipt.root")
    }

    // MARK: - iPad 2-column layout (screen 5)
    //
    // Left: hero (highest elevation) → share tiles → loyalty → actions → pencil banner
    // Right: receipt preview (lowest elevation, supporting context)

    private var iPadBody: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    Spacer(minLength: BrandSpacing.lg)
                    heroSection
                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        Text("Send receipt")
                            .font(.brandLabelSmall().weight(.semibold))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        shareTileGrid
                    }
                    loyaltyCelebration
                    postSaleActionRow
                    // Pencil signature banner — shown only when a signed ticket
                    // exists AND we're on iPad regular size class (per spec item 5).
                    if let ticketId = vm.payload.signedTicketId {
                        pencilSignatureBanner(ticketId: ticketId)
                    }
                    Spacer(minLength: BrandSpacing.xl)
                }
                .padding(.horizontal, BrandSpacing.lg)
            }
            .frame(maxWidth: .infinity)

            // Vertical divider
            Rectangle()
                .fill(Color.bizarreOutline.opacity(0.35))
                .frame(width: 1)

            // Right column — receipt preview
            if let text = receiptText {
                ScrollView {
                    VStack(spacing: BrandSpacing.md) {
                        Spacer(minLength: BrandSpacing.lg)
                        PosReceiptListPreview(receiptText: text)
                            .padding(.horizontal, BrandSpacing.base)
                        Spacer(minLength: BrandSpacing.xl)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Scroll body (iPhone + iPad fallback)

    private var scrollBody: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                Spacer(minLength: BrandSpacing.xl)
                heroSection
                shareTileGrid
                loyaltyCelebration
                if receiptText != nil {
                    receiptPreviewToggle
                }
                postSaleActionRow
                // Note: Pencil signature banner is iPad-only (spec item 5).
                // It appears in the iPadBody left column, not here.
                Spacer(minLength: BrandSpacing.xl)
            }
            .padding(.horizontal, BrandSpacing.base)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Pencil signature banner

    /// Rendered only when `payload.signedTicketId != nil` (per spec item 5).
    /// On iPad this appears in the left column below the action row.
    private func pencilSignatureBanner(ticketId: Int64) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Text("✍")
                .font(.system(size: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Signature captured with Pencil")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreTeal)
                Text("Archived to ticket #\(ticketId) · PKCanvasView")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreTeal.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signature captured with Pencil. Archived to ticket \(ticketId).")
        .accessibilityIdentifier("pos.receipt.pencilBanner")
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: BrandSpacing.md) {
            // Radial glow + check mark
            ZStack {
                // Radial success glow
                RadialGradient(
                    colors: [Color.bizarreSuccess.opacity(0.35), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 80
                )
                .frame(width: 160, height: 160)
                .accessibilityHidden(true)

                Circle()
                    .fill(Color.bizarreSuccess.opacity(0.18))
                    .frame(width: 100, height: 100)
                    .accessibilityHidden(true)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 76, weight: .semibold))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
            }

            // Amount — Barlow Condensed, 54–64pt, Dynamic Type capped
            Text(CartMath.formatCents(vm.payload.amountPaidCents))
                .font(
                    .custom("BarlowCondensed-SemiBold", size: 60, relativeTo: .largeTitle)
                    .leading(.tight)
                )
                .dynamicTypeSize(.large ... .accessibility2)
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityLabel("Amount charged: \(CartMath.formatCents(vm.payload.amountPaidCents))")
                .accessibilityIdentifier("pos.receipt.amount")

            // Method label
            Text(vm.payload.methodLabel)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pos.receipt.methodLabel")

            // Change row for cash
            if let change = vm.payload.changeGivenCents, change > 0 {
                HStack(spacing: BrandSpacing.xs) {
                    Text("Change")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(CartMath.formatCents(change))
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Change given: \(CartMath.formatCents(change))")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pos.receipt.hero")
    }

    // MARK: - Share tile grid

    private var shareTileGrid: some View {
        let isSmsPrimary = vm.defaultChannel == .sms
        let isEmailPrimary = vm.defaultChannel == .email

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: BrandSpacing.sm),
                GridItem(.flexible(), spacing: BrandSpacing.sm),
                GridItem(.flexible(), spacing: BrandSpacing.sm),
                GridItem(.flexible(), spacing: BrandSpacing.sm),
            ],
            spacing: BrandSpacing.sm
        ) {
            PosShareTile(
                systemImage: "message.fill",
                label: "Text",
                isPrimary: isSmsPrimary
            ) {
                vm.share(channel: .sms)
            }

            PosShareTile(
                systemImage: "envelope",
                label: "Email",
                isPrimary: isEmailPrimary
            ) {
                vm.share(channel: .email)
            }

            // Print: uses local UIPrintInteractionController
            printTile

            // AirDrop / system share sheet
            airDropTile
        }
        .accessibilityIdentifier("pos.receipt.shareGrid")
    }

    private var printTile: some View {
        PosShareTile(
            systemImage: "printer",
            label: "Print",
            isPrimary: vm.defaultChannel == .print
        ) {
            vm.share(channel: .print)
        }
        .overlay(
            Group {
                if vm.defaultChannel == .print, let text = receiptText {
                    PosPrintButton(
                        receiptText: text,
                        invoiceLabel: "INV-\(vm.payload.invoiceId)"
                    )
                    .opacity(0) // invisible — tap target backed by PosShareTile
                }
            }
        )
    }

    private var airDropTile: some View {
        Group {
            if let text = receiptText {
                // Wrap in ShareLink so tap opens the system share sheet.
                ShareLink(
                    item: text,
                    preview: SharePreview(
                        "Receipt INV-\(vm.payload.invoiceId)",
                        icon: Image(systemName: "airplayaudio")
                    )
                ) {
                    shareTileLabel(systemImage: "airplayaudio", label: "AirDrop")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AirDrop receipt")
                .accessibilityHint("Opens the system share sheet")
            } else {
                PosShareTile(systemImage: "airplayaudio", label: "AirDrop") {
                    vm.share(channel: .airDrop)
                }
            }
        }
    }

    private func shareTileLabel(systemImage: String, label: String) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.bizarreOnSurface)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.vertical, BrandSpacing.md)
        .padding(.horizontal, BrandSpacing.sm)
        .background(Color.bizarreSurface1.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Send status banner

    @ViewBuilder
    private var sendStatusBanner: some View {
        switch vm.sendStatus {
        case .sending:
            HStack(spacing: BrandSpacing.xs) {
                ProgressView().controlSize(.mini)
                Text("Sending…")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("pos.receipt.sendingSpinner")
        case .sent(let msg):
            Text(msg)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreSuccess)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pos.receipt.sentConfirmation")
        case .failed(let msg):
            Text(msg)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pos.receipt.sendError")
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Loyalty celebration

    @ViewBuilder
    private var loyaltyCelebration: some View {
        if let delta = vm.payload.loyaltyDelta, delta > 0 {
            VStack(spacing: BrandSpacing.xs) {
                sendStatusBanner
                PosLoyaltyCelebrationView(
                    pointsDelta: delta,
                    tierBefore: vm.payload.loyaltyTierBefore,
                    tierAfter: vm.payload.loyaltyTierAfter
                )
            }
        } else {
            sendStatusBanner
        }
    }

    // MARK: - Receipt preview toggle

    private var receiptPreviewToggle: some View {
        Button {
            showReceiptPreview = true
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "doc.text")
                Text("View receipt")
                    .font(.brandBodyMedium())
            }
            .foregroundStyle(.bizarreOrange)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("View full receipt")
        .accessibilityHint("Opens a preview of the receipt text")
        .accessibilityIdentifier("pos.receipt.viewReceiptButton")
    }

    // MARK: - Post-sale action row

    private var postSaleActionRow: some View {
        VStack(spacing: BrandSpacing.sm) {
            // Secondary actions
            HStack(spacing: BrandSpacing.sm) {
                secondaryActionButton(
                    label: "View ticket",
                    systemImage: "ticket",
                    identifier: "pos.receipt.viewTicket"
                ) { vm.viewTicket() }

                secondaryActionButton(
                    label: "Customer",
                    systemImage: "person.circle",
                    identifier: "pos.receipt.viewCustomer"
                ) { vm.viewCustomerProfile() }

                secondaryActionButton(
                    label: "Refund",
                    systemImage: "arrow.uturn.backward.circle",
                    identifier: "pos.receipt.startRefund"
                ) { vm.startRefund() }
            }

            // Primary CTA — next sale
            Button {
                vm.nextSale()
                dismiss()
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "arrow.forward.circle.fill")
                    Text("New sale")
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
            .accessibilityLabel("Start new sale")
            .accessibilityHint("Clears the cart and returns to the POS")
            .accessibilityIdentifier("pos.receipt.newSale")
        }
    }

    private func secondaryActionButton(
        label: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                Text(label)
                    .font(.brandLabelLarge())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
            .foregroundStyle(.bizarreOnSurface)
        }
        .buttonStyle(.bordered)
        .tint(.bizarreOrange)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Receipt preview sheet

    private var receiptPreviewSheet: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if let text = receiptText {
                    PosReceiptListPreview(receiptText: text)
                        .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showReceiptPreview = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview

#Preview("Receipt — SMS primary, loyalty tier-up") {
    PosReceiptView(
        vm: PosReceiptViewModel(
            payload: PosReceiptPayload(
                invoiceId: 42,
                amountPaidCents: 12109,
                changeGivenCents: 891,
                methodLabel: "Cash",
                customerPhone: "+15558675309",
                customerEmail: "jane@example.com",
                loyaltyDelta: 127,
                loyaltyTierBefore: "Gold",
                loyaltyTierAfter: "Platinum"
            )
        ),
        receiptText: "BizarreCRM Demo\n123 Main St\n\nTotal: $121.09\n\nThank you!",
        paidAt: Date()
    )
    .preferredColorScheme(.dark)
}

#Preview("Receipt — Print primary, no loyalty") {
    PosReceiptView(
        vm: PosReceiptViewModel(
            payload: PosReceiptPayload(
                invoiceId: 99,
                amountPaidCents: 5000,
                methodLabel: "Visa •4242"
            )
        ),
        paidAt: Date()
    )
    .preferredColorScheme(.light)
}
#endif
