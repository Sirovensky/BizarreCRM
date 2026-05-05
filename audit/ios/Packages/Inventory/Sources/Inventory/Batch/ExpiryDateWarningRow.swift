#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - ExpiryDateWarningRow

/// §6.8 — Inline warning row shown on any `InventoryLot` when the lot is
/// expired or approaching expiry.
///
/// | State          | Icon                           | Tint              |
/// |----------------|--------------------------------|-------------------|
/// | Expired        | ⚠ exclamationmark.triangle.fill | `.bizarreError`   |
/// | Near expiry    | ⏰ clock.badge.exclamationmark  | `.bizarreWarning` |
/// | OK / no expiry | hidden — view renders nothing  | —                 |
///
/// Usage — embed directly inside a `List` row or `VStack` next to the lot row:
/// ```swift
/// ExpiryDateWarningRow(lot: lot)
/// ```
public struct ExpiryDateWarningRow: View {

    // MARK: Input

    public let lot: InventoryLot

    // MARK: Computed

    private var expiryState: ExpiryState {
        if lot.isExpired    { return .expired }
        if lot.isNearExpiry { return .nearExpiry }
        return .ok
    }

    // MARK: Init

    public init(lot: InventoryLot) {
        self.lot = lot
    }

    // MARK: Body

    public var body: some View {
        switch expiryState {
        case .ok:
            EmptyView()
        case .expired:
            warningRow(
                icon: "exclamationmark.triangle.fill",
                tint: .bizarreError,
                message: expiredMessage
            )
        case .nearExpiry:
            warningRow(
                icon: "clock.badge.exclamationmark",
                tint: .bizarreWarning,
                message: nearExpiryMessage
            )
        }
    }

    // MARK: - Warning row

    private func warningRow(icon: String, tint: Color, message: String) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .imageScale(.small)
                .accessibilityHidden(true)

            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(tint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    // MARK: - Messages

    private var expiredMessage: String {
        guard let date = lot.expiryDate else { return "Lot \(lot.lotId) — expired." }
        return "Lot \(lot.lotId) expired \(relativeDateString(from: date))."
    }

    private var nearExpiryMessage: String {
        guard let date = lot.expiryDate else { return "Lot \(lot.lotId) — expires soon." }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days <= 1 {
            return "Lot \(lot.lotId) expires today."
        }
        return "Lot \(lot.lotId) expires in \(days) day\(days == 1 ? "" : "s")."
    }

    // MARK: - Helpers

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Expiry state

    private enum ExpiryState {
        case ok, nearExpiry, expired
    }
}
#endif
