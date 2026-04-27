import SwiftUI
import DesignSystem
import Networking

// MARK: - §38.5 Segment for targeted offer (§37)
//
// Surfaces a "Create Campaign" shortcut from the membership churn insight
// view, pre-populating the §37 Marketing audience builder with the
// selected churn cohort as a named segment.

// MARK: - Bridge DTO

/// Minimal representation of a §37 marketing segment as needed from Loyalty.
/// Full segment editing lives in Packages/Marketing/Sources/Marketing/SegmentEditorView.swift.
public struct MembershipCohortSegmentSpec: Sendable {
    /// A human-readable name for the auto-generated segment.
    public let segmentName: String
    /// The membership status filter to pre-populate.
    public let membershipStatus: String
    /// Additional context for the campaign (e.g. tier, risk level).
    public let notes: String
}

// MARK: - View

/// Displayed inside `MembershipChurnInsightView` as a "Target this cohort"
/// action row. Opens the Marketing module's campaign create flow with the
/// cohort pre-wired as the audience.
public struct MembershipChurnSegmentLinkView: View {
    public let cohortName: String
    public let memberCount: Int
    public let status: String  // "expiring" | "at_risk" | "churned"
    /// Callback invoked when user taps "Create Campaign".
    /// The caller (host app) navigates to §37 CampaignCreateView.
    public var onCreateCampaign: ((MembershipCohortSegmentSpec) -> Void)?

    public init(
        cohortName: String,
        memberCount: Int,
        status: String,
        onCreateCampaign: ((MembershipCohortSegmentSpec) -> Void)? = nil
    ) {
        self.cohortName = cohortName
        self.memberCount = memberCount
        self.status = status
        self.onCreateCampaign = onCreateCampaign
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Target This Cohort")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
            }

            Text("\(memberCount) \(cohortName.lowercased()) member\(memberCount == 1 ? "" : "s") can receive a targeted campaign via §37 Marketing.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                let spec = MembershipCohortSegmentSpec(
                    segmentName: "\(cohortName) members",
                    membershipStatus: status,
                    notes: "Auto-generated from Membership Churn Insight — \(cohortName)"
                )
                onCreateCampaign?(spec)
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .accessibilityHidden(true)
                    Text("Create Campaign")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityLabel("Create a marketing campaign targeting \(memberCount) \(cohortName.lowercased()) members")
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreOrange.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOrange.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct MembershipChurnSegmentLinkView_Previews: PreviewProvider {
    static var previews: some View {
        MembershipChurnSegmentLinkView(
            cohortName: "Expiring Soon",
            memberCount: 47,
            status: "expiring"
        ) { spec in
            print("Campaign spec:", spec.segmentName)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
