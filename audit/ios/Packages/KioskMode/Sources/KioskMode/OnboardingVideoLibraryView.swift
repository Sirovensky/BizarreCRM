import SwiftUI
import DesignSystem

// MARK: - VideoTile

private struct VideoTile: Sendable {
    let id: Int
    let title: String
    let icon: String
}

// MARK: - VideoPlayerPlaceholderView

/// §51.4 Placeholder video player — AVPlayer integration deferred (TODO).
public struct VideoPlayerPlaceholderView: View {
    let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())

            Text("Video coming soon")
                .font(.body)
                .foregroundStyle(.secondary)
            // TODO: Replace with AVPlayer integration when video assets are ready
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - OnboardingVideoLibraryView

/// §51.4 Placeholder grid of onboarding videos.
/// Full library is out of scope for this PR (TODO: AVPlayer integration).
public struct OnboardingVideoLibraryView: View {
    private let videos: [VideoTile] = [
        VideoTile(id: 0, title: "POS basics",     icon: "creditcard.fill"),
        VideoTile(id: 1, title: "Ticket intake",  icon: "doc.text.fill"),
        VideoTile(id: 2, title: "Invoicing",       icon: "list.bullet.rectangle.fill"),
        VideoTile(id: 3, title: "Inventory",       icon: "shippingbox.fill")
    ]

    @State private var selectedVideo: VideoTile?

    public init() {}

    public var body: some View {
        NavigationStack {
            videoGrid
                .navigationTitle("Training Videos")
                .navigationDestination(item: $selectedVideo) { video in
                    VideoPlayerPlaceholderView(title: video.title)
                }
        }
    }

    // MARK: - Grid layout

    @ViewBuilder
    private var videoGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 160, maximum: 240), spacing: DesignTokens.Spacing.lg)
        ]
        ScrollView {
            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.lg) {
                ForEach(videos) { video in
                    videoTileButton(video)
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }

    @ViewBuilder
    private func videoTileButton(_ video: VideoTile) -> some View {
        Button {
            selectedVideo = video
        } label: {
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: video.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 120)
            .padding(DesignTokens.Spacing.lg)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        }
        .accessibilityLabel(video.title)
        .accessibilityHint("Open training video")
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}

// MARK: - Identifiable conformance for navigation

extension VideoTile: Identifiable, Hashable {
    static func == (lhs: VideoTile, rhs: VideoTile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
