#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - GiftReceiptCheckoutViewModel

/// Drives `GiftReceiptCheckoutSheet`.
///
/// Manages per-line toggle state, channel selection, return-by days input,
/// and return-credit destination.
@MainActor
@Observable
public final class GiftReceiptCheckoutViewModel {

    // MARK: - State

    public var options: GiftReceiptOptions = .default
    public var showPartialPicker: Bool = false

    /// Per-line toggle for partial gift receipt selection.
    /// Key = `SaleLineRecord.id`; value = whether to include in the gift receipt.
    public var lineToggles: [Int64: Bool] = [:]

    // MARK: - Init

    public init(lines: [SaleLineRecord]) {
        // Default: all lines included (partial = false)
        lines.forEach { lineToggles[$0.id] = true }
    }

    // MARK: - Actions

    public func toggleLine(_ id: Int64) {
        lineToggles[id] = !(lineToggles[id] ?? true)
        syncIncludedLines()
    }

    public func selectAllLines(_ lines: [SaleLineRecord]) {
        lines.forEach { lineToggles[$0.id] = true }
        options.includedLineIds = []
    }

    public func applyPartialSelection(_ lines: [SaleLineRecord]) {
        syncIncludedLines()
    }

    // MARK: - Private

    private func syncIncludedLines() {
        // If all lines are selected → clear the set (= full receipt).
        let selected = lineToggles.filter { $0.value }.map { $0.key }
        let deselected = lineToggles.filter { !$0.value }.map { $0.key }
        // Only engage partial mode if at least one line is unchecked.
        options.includedLineIds = deselected.isEmpty ? [] : Set(selected)
    }
}

// MARK: - GiftReceiptCheckoutSheet

/// §16 — Checkout-phase gift-receipt configuration sheet.
///
/// Presented from the tender/receipt flow so the cashier can:
/// 1. Toggle "Include gift receipt" on/off.
/// 2. Choose per-line partial inclusion.
/// 3. Select delivery channel (Print / Email / SMS / AirDrop).
/// 4. Set the return-by window (7 / 14 / 30 / 60 / 90 days).
/// 5. Choose return-credit destination.
///
/// Tapping "Confirm" calls `onConfirm` with the final `GiftReceiptOptions`.
/// Tapping "Skip" calls `onSkip` with a disabled options object.
///
/// ## Placement
/// Present from `PosReceiptView` or `PosPostSaleView` before the receipt
/// is finalised:
/// ```swift
/// .sheet(isPresented: $showGiftReceiptSheet) {
///     GiftReceiptCheckoutSheet(sale: completedSale) { opts in
///         await vm.sendGiftReceipt(options: opts)
///     } onSkip: {
///         // No gift receipt.
///     }
/// }
/// ```
public struct GiftReceiptCheckoutSheet: View {
    public let sale: SaleRecord
    public let onConfirm: @MainActor (GiftReceiptOptions) -> Void
    public let onSkip: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm: GiftReceiptCheckoutViewModel

    public init(
        sale: SaleRecord,
        onConfirm: @escaping @MainActor (GiftReceiptOptions) -> Void,
        onSkip: @escaping @MainActor () -> Void
    ) {
        self.sale      = sale
        self.onConfirm = onConfirm
        self.onSkip    = onSkip
        self._vm = State(initialValue: GiftReceiptCheckoutViewModel(lines: sale.lines))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {

                        // ── Enable toggle ──────────────────────────────────
                        enableSection

                        if vm.options.enabled {
                            // ── Channel picker ─────────────────────────────
                            channelSection

                            // ── Personal message ───────────────────────────
                            messageSection

                            // ── Per-line partial toggle ─────────────────────
                            if sale.lines.count > 1 {
                                partialSection
                            }

                            // ── Return-by window ───────────────────────────
                            returnBySection

                            // ── Return credit ──────────────────────────────
                            returnCreditSection
                        }

                        Spacer(minLength: DesignTokens.Spacing.xxxl)
                    }
                    .padding(.top, DesignTokens.Spacing.lg)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                }
            }
            .navigationTitle("Gift Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                    .accessibilityIdentifier("giftReceiptCheckout.skip")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onConfirm(vm.options)
                        dismiss()
                    }
                    .disabled(!vm.options.enabled)
                    .accessibilityIdentifier("giftReceiptCheckout.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include gift receipt")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Hides prices so the recipient doesn't see what was paid.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Toggle("", isOn: $vm.options.enabled)
                    .labelsHidden()
                    .tint(.bizarrePrimary)
                    .accessibilityIdentifier("giftReceiptCheckout.enableToggle")
            }
        }
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Send via")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(GiftReceiptChannel.allCases, id: \.self) { channel in
                    channelChip(channel)
                }
            }
        }
    }

    private func channelChip(_ channel: GiftReceiptChannel) -> some View {
        Button {
            vm.options.channel = channel
        } label: {
            VStack(spacing: 4) {
                Image(systemName: channel.iconName)
                    .font(.system(size: 18))
                    .accessibilityHidden(true)
                Text(channel.displayName)
                    .font(.brandLabelSmall())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(vm.options.channel == channel
                          ? Color.bizarrePrimary.opacity(0.15)
                          : Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .strokeBorder(
                                vm.options.channel == channel
                                    ? Color.bizarrePrimary
                                    : Color.bizarreOutline.opacity(0.4),
                                lineWidth: vm.options.channel == channel ? 2 : 0.5
                            )
                    )
            )
            .foregroundStyle(vm.options.channel == channel ? .bizarrePrimary : .bizarreOnSurfaceMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(channel.displayName)
        .accessibilityAddTraits(vm.options.channel == channel ? .isSelected : [])
        .accessibilityIdentifier("giftReceiptCheckout.channel.\(channel.rawValue)")
    }

    private var partialSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("Include all items")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.options.includedLineIds.isEmpty },
                    set: { allOn in
                        if allOn {
                            vm.selectAllLines(sale.lines)
                        } else {
                            vm.showPartialPicker = true
                        }
                    }
                ))
                .labelsHidden()
                .tint(.bizarrePrimary)
                .accessibilityIdentifier("giftReceiptCheckout.allItemsToggle")
            }

            if !vm.options.includedLineIds.isEmpty || vm.showPartialPicker {
                VStack(spacing: 0) {
                    ForEach(sale.lines) { line in
                        lineToggleRow(line)
                        if line.id != sale.lines.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
        }
    }

    private func lineToggleRow(_ line: SaleLineRecord) -> some View {
        let included = vm.lineToggles[line.id] ?? true
        return HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: included ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .foregroundStyle(included ? .bizarrePrimary : .bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let sku = line.sku {
                    Text("SKU: \(sku)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            Text("×\(line.quantity)")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggleLine(line.id) }
        .accessibilityLabel("\(line.name), \(included ? "included" : "excluded")")
        .accessibilityAddTraits(included ? .isSelected : [])
        .accessibilityIdentifier("giftReceiptCheckout.line.\(line.id)")
    }

    // MARK: - §16 Gift message

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("Gift message")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text("\(vm.options.message?.count ?? 0)/120")
                    .font(.brandLabelSmall())
                    .foregroundStyle(
                        (vm.options.message?.count ?? 0) >= 120
                            ? .bizarreError
                            : .bizarreOnSurfaceMuted
                    )
            }
            TextField("e.g. Happy Birthday!", text: Binding(
                get: { vm.options.message ?? "" },
                set: { vm.options.message = $0.isEmpty ? nil : String($0.prefix(120)) }
            ), axis: .vertical)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .lineLimit(3, reservesSpace: false)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
            .submitLabel(.done)
            .accessibilityLabel("Gift message, optional")
            .accessibilityIdentifier("giftReceiptCheckout.messageField")
            Text("Printed on the gift receipt; hidden from your copy.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var returnBySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Return within")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Picker("Return window", selection: $vm.options.returnByDays) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("giftReceiptCheckout.returnByPicker")

            Text("Return by: \(vm.options.returnByDateString(from: sale.date))")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var returnCreditSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Gift returns credited to")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            VStack(spacing: 0) {
                ForEach(GiftReceiptReturnCredit.allCases, id: \.self) { credit in
                    Button {
                        vm.options.returnCredit = credit
                    } label: {
                        HStack {
                            Text(credit.displayName)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            if vm.options.returnCredit == credit {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.bizarrePrimary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(credit.displayName)
                    .accessibilityAddTraits(vm.options.returnCredit == credit ? .isSelected : [])
                    .accessibilityIdentifier("giftReceiptCheckout.credit.\(credit.rawValue)")
                    if credit != GiftReceiptReturnCredit.allCases.last {
                        Divider().padding(.leading, DesignTokens.Spacing.md)
                    }
                }
            }
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
    }
}
#endif
