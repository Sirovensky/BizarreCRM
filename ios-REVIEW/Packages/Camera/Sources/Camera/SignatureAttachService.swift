#if canImport(UIKit)
import Foundation
import UIKit
import PencilKit
import Core

// MARK: - SignatureAttachService
//
// §4.8 — "Signature attach — signed customer acknowledgement saved as PNG attachment."
//
// Flow:
//   1. `SignatureAttachService.render(drawing:bounds:scale:)` flattens a
//      `PKDrawing` (PencilKit canvas content) to a `UIImage` then encodes it
//      as a PNG byte buffer.
//   2. `save(drawing:localPhotoId:entityKind:entityId:)` writes the PNG to
//      `AppSupport/photos/{entityKind}/{entityId}/sig-{uuid}.png` via `PhotoStore`
//      (the same actor used for ticket / customer photos — consistent storage path).
//   3. `upload(signatureData:toURL:authToken:)` hands the PNG to
//      `PhotoUploadService.uploadPhoto` for background delivery to the server.
//
// The caller (e.g. `TicketSignOffView`, waiver sheet) is responsible for:
//   - Presenting the `PKCanvasView` for signature collection.
//   - Calling `SignatureAttachService.shared.save(…)` on confirmation.
//   - Passing the returned `localPhotoId` to the audit log or server payload.
//
// Signature PNGs are never JPEG-encoded — lossless preserves the ink detail
// required for legal defensibility of waivers and sign-off records.

// MARK: - SignatureAttachment

/// A saved signature ready for upload.
public struct SignatureAttachment: Sendable {
    /// Unique ID for this signature image (used in the file name + dead-letter tracking).
    public let photoId: UUID
    /// Local file URL of the PNG inside `AppSupport/photos/…`.
    public let localURL: URL
    /// PNG bytes.
    public let pngData: Data
    /// Entity kind this signature was taken for (e.g. `"ticket"`, `"waiver"`).
    public let entityKind: String
    /// Entity identifier string.
    public let entityId: String

    public init(photoId: UUID, localURL: URL, pngData: Data, entityKind: String, entityId: String) {
        self.photoId = photoId
        self.localURL = localURL
        self.pngData = pngData
        self.entityKind = entityKind
        self.entityId = entityId
    }
}

// MARK: - SignatureAttachService

public actor SignatureAttachService {

    // MARK: - Singleton

    public static let shared = SignatureAttachService()

    // MARK: - Constants

    private static let sigSubdirectory = "signatures"

    // MARK: - Init

    public init() {}

    // MARK: - Render

    /// Flattens `drawing` into a PNG `UIImage`.
    ///
    /// - Parameters:
    ///   - drawing:  The `PKDrawing` captured from the `PKCanvasView`.
    ///   - bounds:   The canvas bounds. Defaults to the drawing's natural bounds
    ///               (use the canvas view's `bounds` for a pixel-accurate render).
    ///   - scale:    Pixel scale. Pass `UIScreen.main.scale` (default `2.0` for
    ///               Retina) for a crisp PNG at full device resolution.
    /// - Returns: A lossless `UIImage` of the signature on a white background.
    public func render(
        drawing: PKDrawing,
        bounds: CGRect? = nil,
        scale: CGFloat = 2.0
    ) -> UIImage {
        let rect = bounds ?? drawing.bounds.insetBy(dx: -16, dy: -16)
        // Render the drawing on a white background so the PNG is not transparent —
        // transparent PNGs can look blank on light backgrounds in PDFs.
        let renderer = UIGraphicsImageRenderer(bounds: rect)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(rect)
            drawing.image(from: rect, scale: scale).draw(in: rect)
        }
    }

    // MARK: - Save

    /// Renders `drawing` to PNG and writes it to the local photo store.
    ///
    /// - Parameters:
    ///   - drawing:     The PencilKit drawing to flatten.
    ///   - canvasBounds: The canvas `bounds` at the time of signature (for accurate crop).
    ///   - entityKind:  e.g. `"ticket"`, `"waiver"`, `"checkout"`.
    ///   - entityId:    The entity's ID string.
    /// - Returns: A `SignatureAttachment` with the local URL and PNG data.
    /// - Throws: `SignatureAttachError` on I/O failure.
    public func save(
        drawing: PKDrawing,
        canvasBounds: CGRect? = nil,
        entityKind: String,
        entityId: String
    ) throws -> SignatureAttachment {
        let photoId = UUID()
        let image = render(drawing: drawing, bounds: canvasBounds)

        guard let pngData = image.pngData() else {
            throw SignatureAttachError.encodeFailed
        }

        // Write to AppSupport/photos/{entityKind}/{entityId}/sig-{uuid}.png
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("photos/\(entityKind)/\(entityId)/\(Self.sigSubdirectory)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let fileURL = base.appendingPathComponent("sig-\(photoId.uuidString).png")
        try pngData.write(to: fileURL)

        AppLog.ui.info("SignatureAttachService: saved signature \(photoId) for \(entityKind)/\(entityId) (\(pngData.count / 1024) KB)")
        return SignatureAttachment(
            photoId: photoId,
            localURL: fileURL,
            pngData: pngData,
            entityKind: entityKind,
            entityId: entityId
        )
    }

    // MARK: - Upload

    /// Enqueues the saved signature PNG for background upload via `PhotoUploadService`.
    ///
    /// - Parameters:
    ///   - attachment:  A `SignatureAttachment` returned by `save(drawing:…)`.
    ///   - uploadURL:   Server endpoint (e.g. `POST /api/v1/tickets/{id}/photos`).
    ///   - authToken:   Bearer token for the `Authorization` header.
    /// - Returns: A `PhotoUploadProgress` observable; bind to a progress chip in the UI.
    public func upload(
        attachment: SignatureAttachment,
        to uploadURL: URL,
        authToken: String
    ) async throws -> PhotoUploadProgress {
        try await PhotoUploadService.shared.uploadPhoto(
            data: attachment.pngData,
            to: uploadURL,
            photoId: attachment.photoId,
            entityKind: attachment.entityKind,
            entityId: attachment.entityId,
            authToken: authToken
        )
    }
}

// MARK: - SignatureAttachError

public enum SignatureAttachError: LocalizedError, Sendable {
    case encodeFailed
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Could not encode signature as PNG."
        case .writeFailed(let d):
            return "Could not save signature to disk: \(d)"
        }
    }
}
#endif
