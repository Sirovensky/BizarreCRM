import SwiftUI
import DesignSystem

// MARK: - §38 Refer-a-friend share sheet

/// A modal sheet that lets staff or customers share a personalised referral link.
///
/// Features:
/// - Referral link built from `tenantHandle` + `referralCode`.
/// - "Copy link" button with clipboard feedback.
/// - Native `ShareLink` for OS share sheet (AirDrop, Messages, Mail, etc.).
/// - Points-reward callout ("Both you and your friend earn X points").
/// - Tier badge for the referrer if they are above bronze.
///
/// Presentation:
/// ```swift
/// .sheet(isPresented: $showRefer) {
///     ReferAFriendShareSheet(
///         tenantHandle: "acme-auto",
///         referralCode: "JANE42",
///         referrerTier: .gold,
///         referralBonusPoints: 250
///     )
/// }
/// ```
public struct ReferAFriendShareSheet: View {

    // MARK: - Inputs

    let tenantHandle: String
    let referralCode: String
    let referrerTier: LoyaltyTier
    let referralBonusPoints: Int

    // MARK: - Environment / state

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    // MARK: - Init

    public init(
        tenantHandle: String,
        referralCode: String,
        referrerTier: LoyaltyTier = .bronze,
        referralBonusPoints: Int = 250
    ) {
        self.tenantHandle = tenantHandle
        self.referralCode = referralCode
        self.referrerTier = referrerTier
        self.referralBonusPoints = referralBonusPoints
    }

    // MARK: - Derived

    private var referralURL: URL {
        // Canonical shape: https://biz.re/<handle>?ref=<code>
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "biz.re"
        comps.path = "/\(tenantHandle)"
        comps.queryItems = [URLQueryItem(name: "ref", value: referralCode)]
        return comps.url ?? URL(string: "https://biz.re/\(tenantHandle)?ref=\(referralCode)")!
    }

    private var shareMessage: String {
        "Join me at \(tenantHandle) and we both earn \(referralBonusPoints) loyalty points! \(referralURL.absoluteString)"
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.xl) {
                    headerSection
                    linkSection
                    bonusCallout
                    shareButton
                }
                .padding(BrandSpacing.base)
            }
            .navigationTitle("Refer a Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.xs) {
                Text("Share the Love")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text("Invite friends and earn rewards together")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }

            if referrerTier > .bronze {
                MemberBadge(tier: referrerTier, size: .standard)
            }
        }
        .padding(.top, BrandSpacing.lg)
    }

    // MARK: - Link card

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Your referral link")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            HStack(spacing: BrandSpacing.sm) {
                Text(referralURL.absoluteString)
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    copyLink()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.brandLabelLarge())
                    }
                    .foregroundStyle(copied ? .bizarreSuccess : .bizarreOrange)
                    .animation(.easeInOut(duration: 0.15), value: copied)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Link copied" : "Copy referral link")
            }
            .padding(BrandSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(Color.bizarreOnSurfaceMuted.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Bonus callout

    private var bonusCallout: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "gift.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("You both earn \(referralBonusPoints.formatted(.number)) pts")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Points are added when your friend completes their first visit")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bizarreWarning.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(Color.bizarreWarning.opacity(0.30), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Referral bonus: both you and your friend earn \(referralBonusPoints) loyalty points after their first visit.")
    }

    // MARK: - Share button

    private var shareButton: some View {
        ShareLink(
            item: referralURL,
            message: Text(shareMessage)
        ) {
            Label("Share Link", systemImage: "square.and.arrow.up")
                .font(.brandTitleSmall())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .accessibilityLabel("Open system share sheet to share your referral link")
    }

    // MARK: - Copy helper

    private func copyLink() {
        let text = referralURL.absoluteString
#if canImport(UIKit)
        UIPasteboard.general.string = text
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
