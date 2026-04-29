#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

/// §39 — blocking non-dismissible sheet shown when the POS tab opens with
/// no active cash session. Opening float input + Open CTA. Cancel hands
/// off to the host callback so the POS tab pops back to the prior
/// selection.
public struct OpenRegisterSheet: View {
    public let cashierId: Int64
    public let onOpened: (CashSessionRecord) -> Void
    public let onCancel: () -> Void

    @State private var floatText: String = "0.00"
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    /// §14 — Quick-fill preset amounts for the opening float.
    private static let quickFillAmounts: [(label: String, cents: Int)] = [
        ("$50",  5000),
        ("$100", 10000),
        ("$150", 15000),
        ("$200", 20000),
        ("$250", 25000),
    ]

    public init(cashierId: Int64, onOpened: @escaping (CashSessionRecord) -> Void, onCancel: @escaping () -> Void) {
        self.cashierId = cashierId
        self.onOpened = onOpened
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    header
                    floatField
                    quickFillChips
                    if let err = errorMessage {
                        Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("pos.openRegister.error")
                    }
                    Spacer()
                    openButton
                }
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.vertical, BrandSpacing.lg)
            }
            .navigationTitle("Open register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { BrandHaptics.tap(); onCancel() }
                        .accessibilityIdentifier("pos.openRegister.cancel")
                }
            }
            .interactiveDismissDisabled(true)
        }
    }

    private var header: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Open your register to start selling")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
            Text("Count the cash already in the drawer and enter it below. The Z-report will reconcile against this at close.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, BrandSpacing.md)
        .accessibilityIdentifier("pos.openRegister.header")
    }

    private var floatField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Opening float")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.sm) {
                Text("$").font(.brandHeadlineLarge()).foregroundStyle(.bizarreOnSurfaceMuted).monospacedDigit()
                TextField("0.00", text: $floatText)
                    .keyboardType(.decimalPad)
                    .font(.brandHeadlineLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("pos.openRegister.float")
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(Color.bizarreSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
        }
    }

    // MARK: - §14 Quick-fill chips

    private var quickFillChips: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Quick fill")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(Self.quickFillAmounts, id: \.cents) { preset in
                        Button {
                            BrandHaptics.selection()
                            let dollars = Decimal(preset.cents) / 100
                            floatText = String(format: "%.2f", NSDecimalNumber(decimal: dollars).doubleValue)
                            errorMessage = nil
                        } label: {
                            Text(preset.label)
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOrange)
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(
                                    Capsule()
                                        .fill(Color.bizarreOrange.opacity(0.12))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.bizarreOrange.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .accessibilityLabel("Set opening float to \(preset.label)")
                        .accessibilityIdentifier("pos.openRegister.quickFill.\(preset.cents)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var openButton: some View {
        Button { Task { await commit() } } label: {
            if isSubmitting {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Open register").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .controlSize(.large)
        .disabled(isSubmitting || !isValid)
        .accessibilityIdentifier("pos.openRegister.cta")
    }

    private var isValid: Bool {
        let trimmed = floatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: trimmed) else { return false }
        return value >= 0
    }

    private func commit() async {
        guard !isSubmitting else { return }
        let trimmed = floatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: trimmed), decimal >= 0 else {
            errorMessage = "Enter a non-negative amount."
            return
        }
        let cents = CartMath.toCents(decimal)
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            let record = try await CashRegisterStore.shared.openSession(openingFloat: cents, userId: cashierId)
            // §14 — float-confirmation haptic: double-tap success pattern so
            // cashier feels a distinct "drawer opened" confirmation.
            BrandHaptics.success()
            Task { await HapticCatalog.play(.successConfirm) }
            AppLog.pos.info("POS drawer opened: session=\(record.id ?? -1) float=\(cents)")
            onOpened(record)
        } catch CashRegisterError.alreadyOpen {
            errorMessage = "A session is already open — reloading."
            if let current = try? await CashRegisterStore.shared.currentSession() {
                onOpened(current)
            }
        } catch {
            AppLog.pos.error("POS drawer open failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
#endif
