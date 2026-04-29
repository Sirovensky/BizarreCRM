#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem
import Networking

// MARK: - §5.2 Quick-action row — glass chips

/// Horizontal scrolling row of glass action chips: Call · SMS · Email ·
/// FaceTime · New ticket · New invoice · Share · Merge · Delete.
///
/// Actions that require Phase 4+ navigation (New ticket, New invoice, Delete)
/// are wired to their CTA labels but deeplink routing is deferred.
/// Call / SMS / Email / FaceTime open native OS intents immediately.
public struct CustomerQuickActionRow: View {
    let detail: CustomerDetail
    let api: APIClient

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                // — Call
                if let phone = primaryPhone {
                    actionChip("Call", icon: "phone.fill", tint: .bizarreOrange) {
                        openURL("tel:\(phone.filter(\.isNumber))")
                    }
                }
                // — SMS
                if let phone = primaryPhone {
                    actionChip("SMS", icon: "message.fill", tint: .bizarreTeal) {
                        SMSLauncher.open(phone: phone)
                    }
                }
                // — Email
                if let email = detail.email, !email.isEmpty {
                    actionChip("Email", icon: "envelope.fill", tint: .bizarreSuccess) {
                        openURL("mailto:\(email)")
                    }
                }
                // — FaceTime
                if let phone = primaryPhone {
                    actionChip("FaceTime", icon: "video.fill", tint: .bizarreOrange) {
                        openURL("facetime:\(phone.filter(\.isNumber))")
                    }
                }
                // — New ticket (Phase 4 deeplink; stub)
                actionChip("New ticket", icon: "ticket", tint: .bizarreOnSurfaceMuted) {}
                    .opacity(0.6)
                // — New invoice (Phase 4 deeplink; stub)
                actionChip("New invoice", icon: "doc.text.fill", tint: .bizarreOnSurfaceMuted) {}
                    .opacity(0.6)
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    // MARK: Helpers

    private var primaryPhone: String? {
        [detail.mobile, detail.phone].compactMap { $0?.isEmpty == false ? $0 : nil }.first
    }

    private func openURL(_ str: String) {
        guard let url = URL(string: str) else { return }
        UIApplication.shared.open(url)
    }

    private func actionChip(
        _ label: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}
#endif
