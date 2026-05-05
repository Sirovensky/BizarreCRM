import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §25.4 Share Sheet — Transferable payloads + ShareLink wiring
//
// These types let any SwiftUI view drop in a `ShareLink(item:)` for:
//   • A ticket public-tracking URL (short link → `ShareLink`)
//   • A ticket photo (`UIImage` exported as PNG via `Transferable`)
//   • A watermarked image (logo applied before share)
//
// The shared `ShareItem` namespace from `ShareSheetHelpers.swift` already
// produces the underlying URLs / vCards / PDFs; this file adds the
// SwiftUI-native bridges so consumers don't have to roll their own
// `UIActivityViewController` plumbing.

// MARK: - Public tracking link (§25.4)

/// Transferable wrapper around a public tracking URL.
/// Carries a human-readable preview title (e.g. "Track Ticket #1234")
/// so the share sheet shows context without exposing the short slug.
public struct TrackingLinkPayload: Transferable, Sendable {
    public let url: URL
    public let title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
    }
}

public extension TrackingLinkPayload {
    /// Builds a tracking-link payload from the canonical URL builder
    /// in `ShareItem.trackingURL(...)`. Returns `nil` if the URL can't
    /// be constructed (e.g. self-hosted with no slug).
    static func make(
        shortId: String,
        ticketLabel: String,
        tenantSlug: String?,
        isCloud: Bool
    ) -> TrackingLinkPayload? {
        guard let url = ShareItem.trackingURL(
            shortId: shortId,
            tenantSlug: tenantSlug,
            isCloud: isCloud
        ) else { return nil }
        return TrackingLinkPayload(url: url, title: "Track \(ticketLabel)")
    }
}

// MARK: - Photo (§25.4)

#if canImport(UIKit)
/// Transferable wrapper for ticket photos. Exports as PNG so receivers
/// (Photos, Mail, Messages) get a real image attachment, not a JPEG-of-JPEG.
public struct TicketPhotoPayload: Transferable {
    public let image: UIImage
    public let suggestedName: String

    public init(image: UIImage, suggestedName: String) {
        self.image = image
        self.suggestedName = suggestedName
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { payload in
            guard let data = payload.image.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { $0.suggestedName }
    }
}

// MARK: - Watermarked image (§25.4)

/// Transferable wrapper that applies the BizarreCRM watermark *before*
/// export. Receiver always gets the branded copy; original `UIImage`
/// is never shared raw.
public struct WatermarkedImagePayload: Transferable {
    public let original: UIImage
    public let logoText: String
    public let suggestedName: String

    public init(
        original: UIImage,
        logoText: String = "BizarreCRM",
        suggestedName: String = "image.png"
    ) {
        self.original = original
        self.logoText = logoText
        self.suggestedName = suggestedName
    }

    /// Pre-computes the watermarked image once so it isn't re-rendered
    /// for every export representation.
    private var watermarkedData: Data? {
        original.watermarked(logoText: logoText).pngData()
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { payload in
            guard let data = payload.watermarkedData else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { $0.suggestedName }
    }
}
#endif

// MARK: - SwiftUI ShareLink convenience

public extension View {
    /// §25.4 — Inline `ShareLink` for a public tracking URL.
    /// Use on ticket detail toolbars / context menus.
    @ViewBuilder
    func shareTrackingLink(_ payload: TrackingLinkPayload?) -> some View {
        if let payload {
            ShareLink(
                item: payload,
                subject: Text(payload.title),
                message: Text(payload.title),
                preview: SharePreview(payload.title, image: Image(systemName: "link"))
            )
        } else {
            EmptyView()
        }
    }
}
