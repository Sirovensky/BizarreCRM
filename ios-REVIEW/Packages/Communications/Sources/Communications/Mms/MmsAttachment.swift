import Foundation

// MARK: - MmsAttachmentKind

public enum MmsAttachmentKind: String, Codable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case file

    public var systemImageName: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .file:  return "doc"
        }
    }

    public var displayName: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .file:  return "File"
        }
    }
}

// MARK: - MmsAttachment

/// A media attachment to be sent via MMS.
public struct MmsAttachment: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let kind: MmsAttachmentKind
    /// Local file URL (pre-upload) or remote URL (server-stored).
    public let url: URL
    public let sizeBytes: Int64
    public let mimeType: String
    /// Optional thumbnail URL or local thumbnail image data.
    public let thumbnailURL: URL?

    public init(
        id: UUID = UUID(),
        kind: MmsAttachmentKind,
        url: URL,
        sizeBytes: Int64,
        mimeType: String,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.sizeBytes = sizeBytes
        self.mimeType = mimeType
        self.thumbnailURL = thumbnailURL
    }

    public var formattedSize: String {
        MmsSizeEstimator.formattedSize(bytes: sizeBytes)
    }

    public var accessibilityLabel: String {
        "\(kind.displayName), \(formattedSize)"
    }
}
