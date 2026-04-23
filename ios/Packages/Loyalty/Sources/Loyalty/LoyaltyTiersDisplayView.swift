import SwiftUI
import DesignSystem
import Networking

// MARK: - LoyaltyTiersDisplayViewModel

/// §38 — View-model for `LoyaltyTiersDisplayView`.
///
/// Loads all active membership tiers via `GET /api/v1/membership/tiers`
/// and presents them for customer profile display or settings overview.
@MainActor
@Observable
public final class LoyaltyTiersDisplayViewModel {

    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case comingSoon
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var tiers: [MembershipTierDTO] = []

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func load() async {
        state = .loading
        tiers = []
        do {
            tiers = try await api.listMembershipTiers()
            state = tiers.isEmpty ? .comingSoon : .loaded
        } catch let t as APITransportError {
            if case .httpStatus(let c, _) = t, c == 402 || c == 404 || c == 501 {
                state = .comingSoon
            } else {
                state = .failed(t.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - LoyaltyTiersDisplayView

/// §38 — Read-only display of configured loyalty membership tiers.
///
/// Used in the customer profile "Loyalty" section and in Settings for overview.
///
/// iPhone: vertical `VStack` of tier cards.
/// iPad: 2-column `LazyVGrid` for wider layouts.
///
/// Each tier card shows:
///   - Tier name + discount percentage.
///   - Monthly price.
///   - List of benefits (if any).
///   - Highlighted "current tier" when `activeTierId` matches.
public struct LoyaltyTiersDisplayView: View {

    @State private var vm: LoyaltyTiersDisplayViewModel
    /// Optional: highlight the tier the current customer belongs to.
    private let activeTierId: Int?
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(api: any APIClient, activeTierId: Int? = nil) {
        _vm = State(wrappedValue: LoyaltyTiersDisplayViewModel(api: api))
        self.activeTierId = activeTierId
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .loading:
                loadingView
            case .loaded:
                tiersContent
            case .comingSoon:
                comingSoonView
            case .failed(let msg):
                failedView(msg)
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var tiersContent: some View {
        if hSizeClass == .regular {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: BrandSpacing.md
            ) {
                ForEach(vm.tiers) { tier in
                    tierCard(tier)
                }
            }
        } else {
            VStack(spacing: BrandSpacing.sm) {
                ForEach(vm.tiers) { tier in
                    tierCard(tier)
                }
            }
        }
    }

    // MARK: - Tier card

    private func tierCard(_ tier: MembershipTierDTO) -> some View {
        let isActive = activeTierId == tier.id
        let accentColor = tierAccentColor(tier)

        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            // Header row
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: tierSymbol(tier))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .accessibilityHidden(true)

                Text(tier.name)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)

                Spacer()

                if isActive {
                    Text("CURRENT")
                        .font(.brandLabelSmall())
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xxs)
                        .background(Capsule().fill(accentColor.opacity(0.15)))
                        .accessibilityLabel("Current membership tier")
                }
            }

            // Price row
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xxs) {
                Text(String(format: "$%.2f", tier.monthlyPrice))
                    .font(.brandMono(size: 20))
                    .foregroundStyle(.bizarreOnSurface)
                Text("/ month")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // Discount badge
            if tier.discountPct > 0 {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(accentColor)
                        .accessibilityHidden(true)
                    Text("\(tier.discountPct)% off \(tier.discountAppliesTo ?? "labor")")
                        .font(.brandLabelSmall())
                        .foregroundStyle(accentColor)
                }
            }

            // Benefits
            if !tier.benefits.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    ForEach(tier.benefits, id: \.self) { benefit in
                        Label(benefit, systemImage: "checkmark.seal.fill")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(isActive ? accentColor.opacity(0.08) : Color.bizarreSurface1)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(isActive ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
        )
        .shadow(
            color: Color.black.opacity(DesignTokens.Shadows.sm.opacityLight),
            radius: DesignTokens.Shadows.sm.blur,
            y: DesignTokens.Shadows.sm.y
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tierCardAccessibilityLabel(tier, isActive: isActive))
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Design helpers

    /// Map tier sort order to a design-token color.
    /// Lower sort_order = entry tier = warm color; higher = premium = teal/orange.
    private func tierAccentColor(_ tier: MembershipTierDTO) -> Color {
        // Use the server-supplied hex color if present; fall back to positional.
        if let hex = tier.color {
            return Color(hex: hex) ?? positionalColor(sortOrder: tier.sortOrder)
        }
        return positionalColor(sortOrder: tier.sortOrder)
    }

    private func positionalColor(sortOrder: Int) -> Color {
        switch sortOrder {
        case 0:  return .bizarreWarning    // entry — amber / bronze feel
        case 1:  return .bizarreOnSurface  // mid    — neutral / silver
        case 2:  return .bizarreOrange     // upper  — orange / gold
        default: return .bizarreTeal       // top    — teal / platinum
        }
    }

    private func tierSymbol(_ tier: MembershipTierDTO) -> String {
        switch tier.sortOrder {
        case 0:  return "medal"
        case 1:  return "medal.fill"
        case 2:  return "trophy"
        default: return "crown.fill"
        }
    }

    private func tierCardAccessibilityLabel(_ tier: MembershipTierDTO, isActive: Bool) -> String {
        let activeSuffix = isActive ? ". Your current tier." : ""
        let discount = tier.discountPct > 0 ? " \(tier.discountPct)% discount." : ""
        return "\(tier.name) tier. $\(String(format: "%.2f", tier.monthlyPrice)) per month.\(discount)\(activeSuffix)"
    }

    // MARK: - States

    private var loadingView: some View {
        HStack(spacing: BrandSpacing.sm) {
            ProgressView()
                .accessibilityLabel("Loading loyalty tiers")
            Text("Loading tiers…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
    }

    private var comingSoonView: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "clock")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Loyalty tiers not yet configured")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .accessibilityLabel("Loyalty tiers are not yet configured for this account")
    }

    private func failedView(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Couldn't load tiers")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(message)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button("Retry") { Task { await vm.load() } }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Retry loading loyalty tiers")
        }
        .padding(BrandSpacing.base)
    }
}

// MARK: - Color hex extension (private to this file)

private extension Color {
    /// Initialise from a `#rrggbb` hex string. Returns `nil` for invalid inputs.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
