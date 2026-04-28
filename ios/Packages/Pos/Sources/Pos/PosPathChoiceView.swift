#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosPathChoice

/// §16.28.1 bug 2 — post-gate decision: sell items vs start a repair.
///
/// After the customer gate completes (existing customer / walk-in / new
/// customer / pickup) the cashier needs to declare intent: are we selling
/// products, or starting a repair check-in? Without this step the catalog
/// loads immediately and there is no path into `PosPhase.repair(coordinator)`,
/// which the phase machine already supports but UI never reaches.
public enum PosPathChoice: Sendable, Equatable {
    /// Cashier hasn't decided yet — show `PosPathChoiceView`.
    case undecided
    /// Cashier picked "Sell items" — fall through to the catalog.
    case selling
}

// MARK: - PosPathChoiceView

/// Two large hero tiles ("Sell items" / "Start repair · service") shown
/// in the items column when cart has a customer attached but is otherwise
/// empty. Mockup parity: matches the post-gate decision implied by the
/// transition from `pos-iphone-mockups.html` screen 1 → 2 (catalog) vs
/// 1 → 1b (repair pick-device), and `pos-ipad-mockups.html` similarly.
struct PosPathChoiceView: View {

    /// Customer name shown in the hero header chip.
    let customerName: String

    /// Tap "Sell items" → catalog appears.
    let onSell: () -> Void

    /// Tap "Start repair / service" → enters repair flow coordinator.
    let onStartRepair: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
                .padding(.top, sizeClass == .regular ? 48 : 32)
                .padding(.bottom, sizeClass == .regular ? 32 : 24)

            tiles
                .frame(maxWidth: 720)
                .padding(.horizontal, sizeClass == .regular ? 32 : 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("What's next for \(customerName)?")
                .font(.system(size: sizeClass == .regular ? 26 : 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(Color.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Pick a path · cashier can switch back from the cart at any time.")
                .font(.subheadline)
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Tiles

    @ViewBuilder
    private var tiles: some View {
        if sizeClass == .regular {
            HStack(spacing: 16) {
                tile(emoji: "🛒",
                     title: "Sell items",
                     subtitle: "Open the catalog · scan or tap to add lines.",
                     accent: .primary,
                     shortcut: "⌘ ⇧ S",
                     action: onSell)
                tile(emoji: "🔧",
                     title: "Start repair",
                     subtitle: "Pick device · describe issue · quote · deposit.",
                     accent: .secondary,
                     shortcut: "⌘ ⇧ R",
                     action: onStartRepair)
            }
        } else {
            VStack(spacing: 14) {
                tile(emoji: "🛒",
                     title: "Sell items",
                     subtitle: "Open the catalog · scan or tap to add lines.",
                     accent: .primary,
                     shortcut: nil,
                     action: onSell)
                tile(emoji: "🔧",
                     title: "Start repair",
                     subtitle: "Pick device · describe issue · quote · deposit.",
                     accent: .secondary,
                     shortcut: nil,
                     action: onStartRepair)
            }
        }
    }

    private enum TileAccent { case primary, secondary }

    @ViewBuilder
    private func tile(emoji: String,
                      title: String,
                      subtitle: String,
                      accent: TileAccent,
                      shortcut: String?,
                      action: @escaping () -> Void) -> some View {
        Button(action: {
            BrandHaptics.tapMedium()
            action()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(emoji)
                    .font(.system(size: 34))
                    .padding(.bottom, 2)
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .kerning(-0.3)
                    .foregroundStyle(Color.bizarreOnSurface)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.bizarreOnSurface.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: sizeClass == .regular ? 180 : 132, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent == .primary
                          ? Color.bizarreOnSurface.opacity(0.06)
                          : Color.bizarreOnSurface.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        accent == .primary
                        ? Color.bizarrePrimary.opacity(0.55)
                        : Color.bizarreOnSurface.opacity(0.16),
                        style: StrokeStyle(
                            lineWidth: accent == .primary ? 1.5 : 1,
                            dash: accent == .primary ? [] : [6, 4]
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

#Preview("Sell vs Service") {
    PosPathChoiceView(
        customerName: "Sarah M.",
        onSell: {},
        onStartRepair: {}
    )
    .preferredColorScheme(.dark)
}
#endif
