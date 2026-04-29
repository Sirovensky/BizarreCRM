import SwiftUI
import DesignSystem

// MARK: - ReportEmptyKind  (§91.16 item 2)
//
// Canonical hierarchy for all empty / unavailable states inside the Reports surface.
// Rules:
//  • skeleton  — first load, real data not yet received; show shimmer placeholders.
//  • zero       — data loaded successfully but the selected period has < N transactions.
//  • error      — network or server error; data fetch failed.
//  • offline    — device is offline; cannot fetch live data.

public enum ReportEmptyKind: Equatable, Sendable {
    case skeleton
    case zero
    case error(message: String)
    case offline
}

// MARK: - ReportEmptyView

/// Unified empty-state view that picks the correct presentation for each `ReportEmptyKind`.
/// Used by `ReportsView` and every individual card to stay consistent.
public struct ReportEmptyView: View {

    public let kind: ReportEmptyKind
    /// Optional CTA label + action. Shown on `.zero` and `.error` variants.
    public let ctaLabel: String?
    public let ctaAction: (() -> Void)?

    public init(
        kind: ReportEmptyKind,
        ctaLabel: String? = nil,
        ctaAction: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.ctaLabel = ctaLabel
        self.ctaAction = ctaAction
    }

    public var body: some View {
        switch kind {
        case .skeleton:
            skeletonView
        case .zero:
            unavailableView(
                systemImage: "chart.bar.doc.horizontal",
                title: "No data yet",
                description: "There are no transactions in the selected period."
            )
        case .error(let message):
            unavailableView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load",
                description: message
            )
        case .offline:
            unavailableView(
                systemImage: "wifi.slash",
                title: "You're offline",
                description: "Reports require a network connection. Connect to see your data."
            )
        }
    }

    // MARK: - Skeleton (shimmer placeholders)

    private var skeletonView: some View {
        VStack(spacing: BrandSpacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bizarreSurface1)
                    .frame(height: 20)
                    .shimmerEffect()
            }
        }
        .accessibilityLabel("Loading report data")
    }

    // MARK: - ContentUnavailableView wrapper

    @ViewBuilder
    private func unavailableView(
        systemImage: String,
        title: String,
        description: String
    ) -> some View {
        VStack(spacing: BrandSpacing.md) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
            if let label = ctaLabel, let action = ctaAction {
                Button(action: action) {
                    Text(label)
                        .font(.brandLabelLarge())
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel(label)
            }
        }
    }
}

// MARK: - Shimmer helper (local; mirrors the one in ReportsView)

private extension View {
    func shimmerEffect() -> some View {
        self.opacity(0.45)
    }
}
