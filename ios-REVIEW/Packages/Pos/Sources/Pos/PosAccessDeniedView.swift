#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core

// MARK: - PosAccessDeniedView
//
// §16.1 Permission gate — shown when the current user's role does not include
// `pos.access`. Provides a clear explanation and contact-admin CTA.
//
// Both iPhone and iPad use the same centred-card layout (content width capped
// at 480pt on iPad; full-width on iPhone). Liquid Glass is applied to the
// card surface — it sits on top of `bizarreSurfaceBase` which is content,
// not chrome, so this is a data card in glass, not chrome glass. However
// the card IS treated as a modal alert here (glass on "sheet header" rule),
// which is the closest equivalent in the chrome-glass spec.

public struct PosAccessDeniedView: View {
    let role: PosUserRole
    let onContact: (() -> Void)?

    public init(role: PosUserRole, onContact: (() -> Void)? = nil) {
        self.role = role
        self.onContact = onContact
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            cardContent
                .frame(maxWidth: 480)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var cardContent: some View {
        VStack(spacing: BrandSpacing.lg) {
            // Lock icon
            Image(systemName: "lock.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            // Title + body
            VStack(spacing: BrandSpacing.xs) {
                Text("POS not enabled for this role")
                    .font(.brandTitleLarge())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(bodyText)
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Contact admin CTA — only shown when a contact is available.
            if let onContact {
                Button(action: onContact) {
                    Label("Contact admin", systemImage: "envelope")
                        .font(.brandBodyLarge())
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("posAccessDenied.contactAdmin")
                .accessibilityLabel("Contact administrator to request POS access")
            }
        }
        .padding(BrandSpacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOnSurface.opacity(0.08), lineWidth: 1)
        )
    }

    private var bodyText: String {
        if let contact = role.adminContact {
            return "Your account does not have Point of Sale access. Contact \(contact) to request access."
        }
        return "Your account does not have Point of Sale access. Ask your administrator to enable it for your role."
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Access Denied — with contact") {
    PosAccessDeniedView(
        role: PosUserRole(canAccessPos: false, displayName: "Maria G.", adminContact: "store manager"),
        onContact: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Access Denied — no contact") {
    PosAccessDeniedView(role: PosUserRole(canAccessPos: false, displayName: ""))
        .preferredColorScheme(.dark)
}
#endif

#endif // canImport(UIKit)
