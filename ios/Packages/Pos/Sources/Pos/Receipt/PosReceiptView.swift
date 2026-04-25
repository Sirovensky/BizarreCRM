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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(
        vm: PosReceiptViewModel,
        receiptText: String? = nil,
        paidAt: Date = Date()
    ) {
        self.vm = vm
        self.receiptText = receiptText
        self.paidAt = paidAt
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            scrollBody
        }
        .sensoryFeedback(.success, trigger: paidAt)
        .accessibilityIdentifier("pos.receipt.root")
    }

    // MARK: - Scroll body

    private var scrollBody: some View {
        ScrollView {
            if sizeClass == .regular {
                // iPad: 2-column layout — left (hero + share + loyalty + actions) / right (receipt preview)
                iPadLayout
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xl)
            } else {
                // iPhone: single-column vertical stack
                iPhoneLayout
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xl)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - iPhone layout (single column)

    private var iPhoneLayout: some View {
        VStack(spacing: BrandSpacing.lg) {
            heroSection
            shareTileGrid
            loyaltyCelebration
            if let text = receiptText {
                inlineReceiptPreview(text: text)
            }
            postSaleActionRow
        }
    }

    // MARK: - iPad layout (2-column)

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: BrandSpacing.lg) {
            // Left: hero + share + loyalty + pencil banner + post-sale actions
            VStack(spacing: BrandSpacing.lg) {
                heroSection
                shareTileGrid
                loyaltyCelebration
                pencilSignatureBanner
                postSaleActionRow
            }
            .frame(maxWidth: .infinity)

            // Right: inline receipt preview (lowest elevation per mockup)
            if let text = receiptText {
                inlineReceiptPreview(text: text)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Pencil signature banner (iPad only)

    /// Teal banner shown on iPad receipt when a signature was captured via
    /// Apple Pencil (PKCanvasView). Matches mockup iPad screen 5.
    @ViewBuilder
    private var pencilSignatureBanner: some View {
        if sizeClass == .regular, let ticketId = vm.payload.signedTicketId {
            HStack(spacing: BrandSpacing.sm) {
                Text("✍")
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Signature captured with Pencil")
                        .font(.brandTitleSmall())
                        .foregroundStyle(Color(red: 0.61, green: 0.88, blue: 0.91))
                    Text("Archived to ticket #\(ticketId) · PKCanvasView")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, BrandSpacing.sm + 2)
            .padding(.horizontal, BrandSpacing.md)
            .background(Color(red: 0.30, green: 0.72, blue: 0.79, opacity: 0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(red: 0.30, green: 0.72, blue: 0.79, opacity: 0.30), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Signature captured with Pencil and archived to ticket \(ticketId)")
            .accessibilityIdentifier("pos.receipt.pencilBanner")
        }
    }

    // MARK: - Hero

    /// Celebration hero — highest visual elevation per mockup spec.
    /// Glass container with radial success glow, "Payment complete" label,
    /// hero amount in Barlow Condensed, and cash change row.
    private var heroSection: some View {
        VStack(spacing: BrandSpacing.md) {
            // Radial glow behind check mark
            ZStack {
                RadialGradient(
                    colors: [Color.bizarreSuccess.opacity(0.40), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 90
                )
                .frame(width: 180, height: 180)
                .accessibilityHidden(true)

                Circle()
                    .fill(Color.bizarreSuccess.opacity(0.18))
                    .frame(width: 104, height: 104)
                    .accessibilityHidden(true)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80, weight: .semibold))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
            }

            // "Payment complete" label — matches mockup
            Text("Payment complete")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("pos.receipt.completionLabel")

            // Amount — Barlow Condensed hero, Dynamic Type capped
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

            // Method + optional cash detail
            Text(cashDetailLabel)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pos.receipt.methodLabel")
        }
        .padding(.vertical, BrandSpacing.xl)
        .padding(.horizontal, BrandSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            // Hero highest elevation: glass surface with success-tinted glow
            ZStack {
                Color.bizarreSurface1.opacity(0.85)
                LinearGradient(
                    colors: [Color.bizarreSuccess.opacity(0.06), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            },
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.bizarreSuccess.opacity(0.20), lineWidth: 1)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pos.receipt.hero")
    }

    /// Label combining method + change info for cash transactions.
    private var cashDetailLabel: String {
        var parts = [vm.payload.methodLabel]
        if let change = vm.payload.changeGivenCents, change > 0 {
            parts.append("$\(String(format: "%.2f", Double(change) / 100)) change")
        }
        return parts.joined(separator: " · ")
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

    // MARK: - Inline receipt preview

    /// Inline JetBrains Mono receipt block — matches mockup "receipt-list" section.
    /// Lower visual elevation than the hero per mockup spec.
    private func inlineReceiptPreview(text: String) -> some View {
        PosReceiptListPreview(receiptText: text)
            .accessibilityIdentifier("pos.receipt.inlinePreview")
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
