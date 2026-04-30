import SwiftUI

// MARK: - §30.9 Empty-state illustrations scaffold
//
// Branded flat illustrations for empty states.
// Each illustration is tinted via `.foregroundStyle(.brandPrimary)` per §30.9.
//
// Asset strategy:
//   - SVG assets land in `Assets.xcassets/Illustrations/` (added by designer).
//   - Until SVGs ship, each illustration renders a composed SF Symbol fallback
//     that matches the visual intent.
//   - When the designer drops the real SVG into the asset catalog, replace the
//     `Image(systemName:)` call with `Image("Illustration.<name>")` — no other
//     code changes needed (the `.illustrationModifier` wrapper handles sizing).
//
// Usage:
//   BrandIllustration(.emptyTickets)
//       .foregroundStyle(.brandPrimary)    // brand tint per §30.9
//       .frame(width: 120, height: 120)

// MARK: - IllustrationType

public enum IllustrationType: String, CaseIterable, Sendable {
    // Core empty states
    case emptyTickets       = "Illustration.EmptyTickets"
    case emptyInventory     = "Illustration.EmptyInventory"
    case emptySMS           = "Illustration.EmptySMS"
    case emptyCustomers     = "Illustration.EmptyCustomers"
    case emptyInvoices      = "Illustration.EmptyInvoices"
    case emptyAppointments  = "Illustration.EmptyAppointments"
    case emptyReports       = "Illustration.EmptyReports"
    case emptySearch        = "Illustration.EmptySearch"
    case emptyNotifications = "Illustration.EmptyNotifications"

    // Error / status states
    case offlineError       = "Illustration.Offline"
    case serverError        = "Illustration.ServerError"
    case permissionDenied   = "Illustration.PermissionDenied"

    // Onboarding
    case onboardingWelcome  = "Illustration.OnboardingWelcome"
    case onboardingComplete = "Illustration.OnboardingComplete"

    // MARK: SF Symbol fallback (used until real SVG assets ship)
    var fallbackSymbol: String {
        switch self {
        case .emptyTickets:       return "ticket"
        case .emptyInventory:     return "shippingbox"
        case .emptySMS:           return "bubble.left.and.bubble.right"
        case .emptyCustomers:     return "person.2"
        case .emptyInvoices:      return "doc.text"
        case .emptyAppointments:  return "calendar"
        case .emptyReports:       return "chart.bar"
        case .emptySearch:        return "magnifyingglass"
        case .emptyNotifications: return "bell"
        case .offlineError:       return "wifi.slash"
        case .serverError:        return "exclamationmark.triangle"
        case .permissionDenied:   return "lock.shield"
        case .onboardingWelcome:  return "star.circle"
        case .onboardingComplete: return "checkmark.seal"
        }
    }
}

// MARK: - BrandIllustration view

/// Renders a named illustration with graceful fallback to SF Symbols.
///
/// Tint via `.foregroundStyle(...)` on the caller — not baked into this view —
/// so the same illustration can appear in different brand contexts.
public struct BrandIllustration: View {
    let type: IllustrationType

    public init(_ type: IllustrationType) {
        self.type = type
    }

    public var body: some View {
        Group {
            // Try the real asset catalog image first; fall back to SF Symbol.
            if let _ = UIImage(named: type.rawValue) {
                Image(type.rawValue)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: type.fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .accessibilityHidden(true)   // decorative — parent empty-state provides context
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Empty state illustrations") {
    ScrollView {
        LazyVGrid(columns: [.init(), .init(), .init()], spacing: 24) {
            ForEach(IllustrationType.allCases, id: \.rawValue) { type in
                VStack(spacing: 8) {
                    BrandIllustration(type)
                        .brandIllustrationTinted()   // §30.9 brand-tint convenience
                        .frame(width: 60, height: 60)
                    Text(type.rawValue.split(separator: ".").last.map(String.init) ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
#endif
