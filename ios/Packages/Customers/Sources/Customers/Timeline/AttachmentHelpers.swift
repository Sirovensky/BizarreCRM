#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - §5.7 Attachment helpers (file-size formatter + mime-type icon)

// MARK: FileSizeFormatter

/// Shared file-size formatting helper used across attachment and file-list surfaces.
/// Wraps `ByteCountFormatter` for consistent KB / MB / GB display.
public enum FileSizeFormatter {

    /// Returns a human-readable byte count string using adaptive units
    /// (KB for < 1 MB, MB for < 1 GB, GB otherwise).
    public static func string(fromBytes bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle   = .file
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: MimeTypeIcon

/// Maps a MIME-type string to a SF Symbol name and an accent colour for
/// use in file lists, attachment rows, and thumbnail placeholders.
public struct MimeTypeIcon {

    /// SF Symbol name that best represents the MIME type.
    public let symbolName: String
    /// Suggested tint colour for the icon.
    public let tintColor: Color

    // MARK: Lookup

    /// Returns the icon descriptor for a given MIME type string.
    /// Falls back to a generic document icon for unknown types.
    public static func resolve(mimeType: String) -> MimeTypeIcon {
        switch mimeType {

        // Images
        case let m where m.hasPrefix("image/"):
            return MimeTypeIcon(symbolName: "photo", tintColor: .bizarreTeal)

        // Video
        case let m where m.hasPrefix("video/"):
            return MimeTypeIcon(symbolName: "video", tintColor: .bizarreOrange)

        // Audio
        case let m where m.hasPrefix("audio/"):
            return MimeTypeIcon(symbolName: "waveform", tintColor: .bizarreOrange)

        // PDF
        case "application/pdf":
            return MimeTypeIcon(symbolName: "doc.richtext", tintColor: .red)

        // Word-processing
        case "application/msword",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
            return MimeTypeIcon(symbolName: "doc.text", tintColor: .blue)

        // Spreadsheets
        case "application/vnd.ms-excel",
             "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
             "text/csv":
            return MimeTypeIcon(symbolName: "tablecells", tintColor: .green)

        // Presentations
        case "application/vnd.ms-powerpoint",
             "application/vnd.openxmlformats-officedocument.presentationml.presentation":
            return MimeTypeIcon(symbolName: "play.rectangle", tintColor: .orange)

        // Archives
        case "application/zip",
             "application/x-tar",
             "application/gzip",
             "application/x-7z-compressed",
             "application/x-rar-compressed":
            return MimeTypeIcon(symbolName: "doc.zipper", tintColor: .brown)

        // Plain text
        case let m where m.hasPrefix("text/"):
            return MimeTypeIcon(symbolName: "doc.text", tintColor: .bizarreOnSurfaceMuted)

        // Default
        default:
            return MimeTypeIcon(symbolName: "doc", tintColor: .bizarreOnSurfaceMuted)
        }
    }
}

// MARK: AttachmentThumbnailPlaceholder

/// Shimmer-style placeholder shown while an attachment thumbnail is loading
/// or when no thumbnail image is available.
///
/// Usage:
/// ```swift
/// AsyncImage(url: url) { phase in
///     switch phase {
///     case .success(let img): img.resizable().scaledToFill()
///     default: AttachmentThumbnailPlaceholder(mimeType: file.mimeType)
///     }
/// }
/// ```
public struct AttachmentThumbnailPlaceholder: View {

    let mimeType: String
    let showShimmer: Bool

    public init(mimeType: String, showShimmer: Bool = true) {
        self.mimeType  = mimeType
        self.showShimmer = showShimmer
    }

    @State private var shimmerPhase: CGFloat = -1

    public var body: some View {
        let icon = MimeTypeIcon.resolve(mimeType: mimeType)
        ZStack {
            Color.bizarreSurface2

            Image(systemName: icon.symbolName)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(icon.tintColor.opacity(0.8))
                .accessibilityHidden(true)

            if showShimmer {
                shimmerOverlay
            }
        }
        .onAppear {
            guard showShimmer else { return }
            withAnimation(
                .linear(duration: 1.4)
                .repeatForever(autoreverses: false)
            ) {
                shimmerPhase = 1
            }
        }
    }

    // MARK: Shimmer

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear,           location: 0),
                    .init(color: .white.opacity(0.18), location: 0.45),
                    .init(color: .white.opacity(0.30), location: 0.5),
                    .init(color: .white.opacity(0.18), location: 0.55),
                    .init(color: .clear,           location: 1),
                ]),
                startPoint: .leading,
                endPoint:   .trailing
            )
            .frame(width: w * 2.5)
            .offset(x: shimmerPhase * w * 2.5 - w * 1.25)
            .allowsHitTesting(false)
        }
        .clipped()
    }
}

// MARK: - AttachmentRemovalConfirmation modifier

/// Presents a destructive confirmation dialog before deleting an attachment.
///
/// The caller passes a `Binding<T?>` (`pendingDelete`). When the binding is
/// set to a non-nil value the dialog appears; accepting fires `onConfirm`,
/// cancelling clears the binding.
///
/// Usage:
/// ```swift
/// Button("Delete") { pendingDelete = file }
/// .attachmentRemovalConfirmation(
///     item: $pendingDelete,
///     fileName: { $0.name },
///     onConfirm: { file in await vm.deleteFile(file) }
/// )
/// ```
extension View {
    public func attachmentRemovalConfirmation<T: Identifiable & Sendable>(
        item: Binding<T?>,
        fileName: @escaping (T) -> String,
        onConfirm: @escaping (T) async -> Void
    ) -> some View {
        self.modifier(
            AttachmentRemovalConfirmationModifier(
                item: item,
                fileName: fileName,
                onConfirm: onConfirm
            )
        )
    }
}

private struct AttachmentRemovalConfirmationModifier<T: Identifiable & Sendable>: ViewModifier {
    @Binding var item: T?
    let fileName: (T) -> String
    let onConfirm: (T) async -> Void

    // Derived computed binding so the dialog appears whenever `item` is non-nil.
    private var isPresented: Binding<Bool> {
        Binding(
            get: { item != nil },
            set: { if !$0 { item = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove Attachment",
                isPresented: isPresented,
                titleVisibility: .visible
            ) {
                if let t = item {
                    Button("Delete \"\(fileName(t))\"", role: .destructive) {
                        let captured = t
                        item = nil
                        Task { await onConfirm(captured) }
                    }
                }
                Button("Cancel", role: .cancel) { item = nil }
            } message: {
                if let t = item {
                    Text(verbatim: "\u{201C}\(fileName(t))\u{201D} will be permanently deleted. This cannot be undone.")
                }
            }
    }
}

#endif
