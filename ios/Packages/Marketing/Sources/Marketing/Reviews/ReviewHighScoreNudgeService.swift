import SwiftUI
import SafariServices
import DesignSystem
import Networking

// §37.5 — After high NPS (9-10) or high CSAT (4-5 stars), nudge the customer
// to leave a public review via share sheet. No auto-post; no third-party API
// calls; external links open in SFSafariViewController (sovereignty §28).

// MARK: - ReviewNudgeThresholds

/// Configurable score thresholds that trigger a review nudge.
public struct ReviewNudgeThresholds: Sendable {
    /// Minimum NPS score (0-10) to trigger a nudge. Google/Yelp ToS: ≥9 only.
    public var minNPSScore: Int
    /// Minimum CSAT score (1-5) to trigger a nudge.
    public var minCSATScore: Int

    public static let `default` = ReviewNudgeThresholds(minNPSScore: 9, minCSATScore: 4)

    public init(minNPSScore: Int, minCSATScore: Int) {
        self.minNPSScore = minNPSScore
        self.minCSATScore = minCSATScore
    }
}

// MARK: - ReviewNudgeService

/// After a positive survey response, checks rate-limit then surfaces a share
/// sheet so the customer can leave a public review. iOS never calls third-party
/// review APIs directly — the URL is opened in SFSafariViewController.
public actor ReviewHighScoreNudgeService {

    private let api: APIClient
    private let thresholds: ReviewNudgeThresholds

    public init(api: APIClient, thresholds: ReviewNudgeThresholds = .default) {
        self.api = api
        self.thresholds = thresholds
    }

    // MARK: - Public interface

    /// Returns a `ReviewNudgePayload` when the customer qualifies for a nudge,
    /// or `nil` if the score is too low or the customer was asked within 180 days.
    public func nudgePayload(
        customerId: String,
        npsScore: Int? = nil,
        csatScore: Int? = nil,
        platforms: ReviewPlatformSettings
    ) async throws -> ReviewNudgePayload? {
        // 1. Score gate — must pass at least one threshold.
        let qualifiesNPS  = npsScore.map  { $0 >= thresholds.minNPSScore  } ?? false
        let qualifiesCSAT = csatScore.map { $0 >= thresholds.minCSATScore } ?? false
        guard qualifiesNPS || qualifiesCSAT else { return nil }

        // 2. Rate-limit gate (180 days — §37.5).
        let lastRequest = try await api.getReviewLastRequest(customerId: customerId)
        if let lastDate = lastRequest.lastRequestedAt {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            guard daysSince > ReviewSolicitationService.rateLimitDays else { return nil }
        }

        // 3. Build ordered list of configured platform URLs (sovereignty: URLs only, no SDK).
        var destinations: [ReviewNudgeDestination] = []
        if let url = platforms.googleBusinessURL {
            destinations.append(ReviewNudgeDestination(platform: .google, url: url))
        }
        if let url = platforms.yelpURL {
            destinations.append(ReviewNudgeDestination(platform: .yelp, url: url))
        }
        if let url = platforms.facebookURL {
            destinations.append(ReviewNudgeDestination(platform: .facebook, url: url))
        }
        for other in platforms.otherPlatforms {
            destinations.append(ReviewNudgeDestination(
                platform: .other(name: other.name, url: other.url),
                url: other.url
            ))
        }
        guard !destinations.isEmpty else { return nil }

        return ReviewNudgePayload(customerId: customerId, destinations: destinations)
    }
}

// MARK: - ReviewNudgePayload

public struct ReviewNudgePayload: Sendable {
    public let customerId: String
    public let destinations: [ReviewNudgeDestination]

    public init(customerId: String, destinations: [ReviewNudgeDestination]) {
        self.customerId = customerId
        self.destinations = destinations
    }
}

// MARK: - ReviewNudgeDestination

public struct ReviewNudgeDestination: Sendable, Identifiable {
    public let id: String
    public let platform: ReviewPlatform
    /// The tenant-configured review URL. Never a third-party SDK call.
    public let url: URL

    public init(platform: ReviewPlatform, url: URL) {
        self.id = platform.displayName
        self.platform = platform
        self.url = url
    }
}

// MARK: - ReviewNudgeSheet

/// Shown after a high CSAT or NPS response. Lets customer (via staff) choose a
/// platform and open it in SFSafariViewController. No auto-post (Google/Yelp ToS).
@MainActor
public struct ReviewNudgeSheet: View {
    public let payload: ReviewNudgePayload
    /// Called when a platform is tapped; caller is responsible for opening the URL.
    public let onOpenURL: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(payload: ReviewNudgePayload, onOpenURL: @escaping (URL) -> Void) {
        self.payload = payload
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                headerSection
                platformList
                Spacer()
                tosDisclaimer
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Leave a Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                        .accessibilityLabel("Dismiss review nudge")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "star.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            Text("Glad you're happy!")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)

            Text("Would you mind sharing your experience on one of these platforms? It only takes a moment.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Platform list

    private var platformList: some View {
        VStack(spacing: BrandSpacing.sm) {
            ForEach(payload.destinations) { destination in
                platformButton(destination)
            }
        }
    }

    private func platformButton(_ destination: ReviewNudgeDestination) -> some View {
        Button {
            // Opens in SFSafariViewController — never calls third-party API (§28).
            onOpenURL(destination.url)
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: destination.platform.systemIconName)
                    .font(.system(size: 22))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(destination.platform.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(.brandGlass, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .accessibilityLabel("Leave a review on \(destination.platform.displayName)")
        .accessibilityHint("Opens \(destination.platform.displayName) in Safari")
    }

    // MARK: - ToS disclaimer

    /// Block tying reviews to discounts — Google/Yelp ToS §37.5.
    private var tosDisclaimer: some View {
        Text("We're sharing this because we value your feedback. This is not tied to any discount, offer, or reward.")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, BrandSpacing.lg)
            .accessibilityLabel("Disclaimer: reviews are not tied to discounts or offers")
    }
}
