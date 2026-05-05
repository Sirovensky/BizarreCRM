import SwiftUI
import Core
import DesignSystem

// MARK: - MmsAttachmentBubbleView

/// Inline media preview inside an SMS thread bubble.
/// Tap opens a full-screen preview sheet.
/// Obeys Reduce Motion — disables spring transition when setting is active.
public struct MmsAttachmentBubbleView: View {
    let attachment: MmsAttachment
    @State private var showFullScreen: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(attachment: MmsAttachment) {
        self.attachment = attachment
    }

    public var body: some View {
        Button {
            showFullScreen = true
        } label: {
            thumbnail
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 220, maxHeight: 180)
        .accessibilityLabel(attachment.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to preview full screen")
        .sheet(isPresented: $showFullScreen) {
            MmsFullScreenPreview(attachment: attachment)
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        switch attachment.kind {
        case .image:
            AsyncImage(url: attachment.url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    placeholderIcon("photo.badge.exclamationmark")
                case .empty:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    placeholderIcon("photo")
                }
            }
        case .video:
            ZStack {
                Color.bizarreSurface2
                VStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    Text(attachment.formattedSize)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        case .audio:
            ZStack {
                Color.bizarreSurface2
                VStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    Text(attachment.formattedSize)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        case .file:
            ZStack {
                Color.bizarreSurface2
                VStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    Text(attachment.url.lastPathComponent)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.xs)
                    Text(attachment.formattedSize)
                        .font(.brandMono(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
    }

    private func placeholderIcon(_ name: String) -> some View {
        ZStack {
            Color.bizarreSurface2
            Image(systemName: name)
                .font(.system(size: 32))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - MmsFullScreenPreview

private struct MmsFullScreenPreview: View {
    let attachment: MmsAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle(attachment.kind.displayName)
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch attachment.kind {
        case .image:
            AsyncImage(url: attachment.url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                default:
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .accessibilityLabel(attachment.accessibilityLabel)
        case .video, .audio:
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: attachment.kind == .video ? "play.rectangle.fill" : "waveform")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
                Text("Playback not available in preview")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .file:
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
                Text(attachment.url.lastPathComponent)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.white)
                Text(attachment.formattedSize)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
