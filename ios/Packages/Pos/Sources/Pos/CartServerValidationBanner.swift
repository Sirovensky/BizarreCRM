#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - CartServerValidationBanner (§16)
//
// When the POS submits a cart for checkout the server re-validates:
//   - Tax amounts (rounding + rate changes since catalog load)
//   - Discount eligibility (first-time customer, loyalty tier, usage limits)
//   - Price overrides (server-side rule wins over client-side optimistic price)
//
// If server total differs from client total, this banner surfaces the delta
// so the cashier can explain the discrepancy to the customer.
//
// UX:
//   - Amber warning for < $1 delta (common rounding edge case)
//   - Red warning for ≥ $1 delta (unexpected — cashier should review)
//   - Tapping the banner opens `CartServerValidationDetailSheet`
//   - Dismissed automatically when cart resets for next sale

// MARK: - ServerValidationMismatch

/// Describes a mismatch between client-computed and server-returned cart total.
public struct ServerValidationMismatch: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case taxRecomputed
        case discountInvalidated(ruleName: String)
        case priceAdjusted(itemName: String)
        case unknown
    }

    public let kind: Kind
    /// Signed delta in cents (positive = server is higher, negative = server is lower).
    public let deltaCents: Int
    /// Human-readable reason from the server error/message field.
    public let serverMessage: String?

    public init(kind: Kind, deltaCents: Int, serverMessage: String? = nil) {
        self.kind          = kind
        self.deltaCents    = deltaCents
        self.serverMessage = serverMessage
    }

    public var isSignificant: Bool { abs(deltaCents) >= 100 } // ≥ $1.00

    public var bannerText: String {
        let amount = CartMath.formatCents(abs(deltaCents))
        let direction = deltaCents > 0 ? "+" : "−"
        switch kind {
        case .taxRecomputed:
            return "Tax recomputed (\(direction)\(amount))"
        case .discountInvalidated(let name):
            return "Discount "\(name)" removed (\(direction)\(amount))"
        case .priceAdjusted(let item):
            return "Price adjusted for \(item) (\(direction)\(amount))"
        case .unknown:
            return "Total adjusted by server (\(direction)\(amount))"
        }
    }
}

// MARK: - CartServerValidationBannerView

/// Dismissible banner shown when the server total differs from the client total.
///
/// Attach to the cart root view:
/// ```swift
/// PosCartView(cart: cart)
///     .overlay(alignment: .top) {
///         if let mismatch = posVM.serverValidationMismatch {
///             CartServerValidationBannerView(mismatch: mismatch) {
///                 posVM.dismissServerValidationMismatch()
///             }
///             .transition(.move(edge: .top).combined(with: .opacity))
///         }
///     }
/// ```
public struct CartServerValidationBannerView: View {

    public let mismatch: ServerValidationMismatch
    public let onDismiss: () -> Void

    @State private var showDetail: Bool = false

    public init(mismatch: ServerValidationMismatch, onDismiss: @escaping () -> Void) {
        self.mismatch  = mismatch
        self.onDismiss = onDismiss
    }

    private var accentColor: Color {
        mismatch.isSignificant ? .red : .bizarreWarning
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: mismatch.isSignificant ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(accentColor)
                .font(.system(size: 16, weight: .medium))
                .accessibilityHidden(true)

            Text(mismatch.bannerText)
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(2)

            Spacer()

            Button {
                showDetail = true
            } label: {
                Text("Details")
                    .font(.brandLabelSmall())
                    .foregroundStyle(accentColor)
            }
            .accessibilityIdentifier("cartMismatch.details")

            Button {
                onDismiss()
                BrandHaptics.tap()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreMutedForeground)
                    .font(.system(size: 18))
            }
            .accessibilityLabel("Dismiss server validation warning")
            .accessibilityIdentifier("cartMismatch.dismiss")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(accentColor.opacity(0.10))
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundStyle(accentColor.opacity(0.6)),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mismatch.bannerText + ". Tap Details to see more.")
        .sheet(isPresented: $showDetail) {
            CartServerValidationDetailSheet(mismatch: mismatch, onDismiss: onDismiss)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - CartServerValidationDetailSheet

public struct CartServerValidationDetailSheet: View {

    public let mismatch: ServerValidationMismatch
    public let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(mismatch: ServerValidationMismatch, onDismiss: @escaping () -> Void) {
        self.mismatch  = mismatch
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            // Handle
            Capsule()
                .fill(Color.bizarreOutline)
                .frame(width: 36, height: 4)
                .padding(.top, BrandSpacing.sm)

            Image(systemName: mismatch.isSignificant ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(mismatch.isSignificant ? .red : .bizarreWarning)
                .accessibilityHidden(true)

            Text(mismatch.bannerText)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)

            if let msg = mismatch.serverMessage {
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreMutedForeground)
                    .multilineTextAlignment(.center)
            }

            // Delta detail row
            HStack {
                Text("Server adjustment")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                let delta = mismatch.deltaCents
                Text(delta > 0
                     ? "+ \(CartMath.formatCents(delta))"
                     : "− \(CartMath.formatCents(-delta))")
                    .font(.brandBodyLarge().monospacedDigit())
                    .foregroundStyle(delta > 0 ? .red : .bizarreSuccess)
            }
            .padding(BrandSpacing.md)
            .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))

            Text("The cart total has been updated to match the server. Please confirm with the customer before proceeding.")
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreMutedForeground)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                dismiss()
                onDismiss()
            } label: {
                Text("Understood")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .controlSize(.large)
            .accessibilityIdentifier("cartMismatch.understood")
        }
        .padding(.horizontal, BrandSpacing.xl)
        .padding(.bottom, BrandSpacing.xl)
    }
}

// MARK: - Preview

#Preview("Tax recomputed banner") {
    VStack {
        CartServerValidationBannerView(
            mismatch: ServerValidationMismatch(
                kind: .taxRecomputed,
                deltaCents: 3,
                serverMessage: "Sales tax rate for your location changed since the cart was loaded."
            ),
            onDismiss: { print("Dismissed") }
        )
        Spacer()
    }
    .preferredColorScheme(.dark)
}

#Preview("Significant mismatch banner") {
    VStack {
        CartServerValidationBannerView(
            mismatch: ServerValidationMismatch(
                kind: .discountInvalidated(ruleName: "Summer Flash 20%"),
                deltaCents: 2450,
                serverMessage: "Discount usage limit reached — the code has been redeemed the maximum number of times."
            ),
            onDismiss: { print("Dismissed") }
        )
        Spacer()
    }
    .preferredColorScheme(.dark)
}
#endif
