#if canImport(UIKit)
import UIKit
import PDFKit
import CoreGraphics

// MARK: - Input types

public struct PhotoReportPage: Sendable {
    public let image: UIImage
    /// Optional caption displayed beneath the photo.
    public let caption: String?
    /// "pre" or "post" classification label (or nil if untagged).
    public let tag: String?

    public init(image: UIImage, caption: String? = nil, tag: String? = nil) {
        self.image = image
        self.caption = caption
        self.tag = tag
    }
}

public struct PhotoReportMetadata: Sendable {
    public let title: String
    public let ticketId: String
    public let technicianName: String?
    public let date: Date

    public init(
        title: String,
        ticketId: String,
        technicianName: String? = nil,
        date: Date = Date()
    ) {
        self.title = title
        self.ticketId = ticketId
        self.technicianName = technicianName
        self.date = date
    }
}

// MARK: - Error

public enum PhotoReportError: LocalizedError, Sendable {
    case noPages
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .noPages:       return "Cannot generate a PDF report with no photos."
        case .renderFailed:  return "PDF rendering failed."
        }
    }
}

// MARK: - Builder

/// Pure function that produces a PDF `Data` from an array of `UIImage` values
/// with a title + date header on the first page. No mutable shared state.
public enum PhotoReportPdfBuilder {

    // MARK: - Layout constants

    private static let pageSize  = CGSize(width: 595, height: 842)  // A4 points
    private static let margin: CGFloat   = 40
    private static let headerHeight: CGFloat = 80
    private static let footerHeight: CGFloat = 24
    private static let captionHeight: CGFloat = 20
    private static let photoSpacing: CGFloat = 16

    // MARK: - Public API

    /// Builds a PDF report from the supplied pages and metadata.
    ///
    /// - Parameters:
    ///   - pages: Ordered list of `PhotoReportPage` values; must not be empty.
    ///   - metadata: Title, ticket ID, and date that appear in the header.
    /// - Returns: PDF data ready to write to disk or share via `UIActivityViewController`.
    public static func build(
        pages: [PhotoReportPage],
        metadata: PhotoReportMetadata
    ) throws -> Data {
        guard !pages.isEmpty else { throw PhotoReportError.noPages }

        let pdfData = NSMutableData()
        let pageRect = CGRect(origin: .zero, size: pageSize)
        var mediaBox = pageRect

        UIGraphicsBeginPDFContextToData(pdfData, pageRect, pdfDocumentInfo(metadata: metadata))

        // Lay out photos, 2 per row, starting after the header on page 1.
        let contentWidth = pageSize.width - margin * 2
        let cellWidth = (contentWidth - photoSpacing) / 2
        let cellHeight = cellWidth * 0.75  // 4:3 aspect

        var currentY: CGFloat = 0
        var isFirstPage = true
        var columnIndex = 0

        for (idx, page) in pages.enumerated() {
            // Determine x position
            let x = margin + CGFloat(columnIndex) * (cellWidth + photoSpacing)

            // If we need a new page row start
            if columnIndex == 0 {
                if isFirstPage {
                    UIGraphicsBeginPDFPageWithInfo(pageRect, nil)
                    drawHeader(metadata: metadata, in: pageRect)
                    currentY = margin + headerHeight
                    isFirstPage = false
                } else if currentY + cellHeight + captionHeight + photoSpacing > pageSize.height - margin - footerHeight {
                    drawFooter(pageNumber: pageIndex(for: idx, perRow: 2) + 1, in: pageRect)
                    UIGraphicsBeginPDFPageWithInfo(pageRect, nil)
                    currentY = margin
                }
            }

            let photoRect = CGRect(x: x, y: currentY, width: cellWidth, height: cellHeight)
            drawPhoto(page: page, in: photoRect)

            // Move to next column or next row
            if columnIndex == 0 {
                columnIndex = 1
            } else {
                drawFooter(
                    pageNumber: pageIndex(for: idx, perRow: 2) + 1,
                    in: pageRect
                )
                columnIndex = 0
                currentY += cellHeight + captionHeight + photoSpacing
            }
        }

        // Close last page if it had an odd number of photos
        if columnIndex == 1 {
            drawFooter(pageNumber: pageIndex(for: pages.count - 1, perRow: 2) + 1, in: pageRect)
        }

        UIGraphicsEndPDFContext()

        guard pdfData.length > 0 else { throw PhotoReportError.renderFailed }
        return pdfData as Data
    }

    // MARK: - Draw helpers

    private static func drawHeader(metadata: PhotoReportMetadata, in rect: CGRect) {
        let headerRect = CGRect(x: margin, y: margin, width: rect.width - margin * 2, height: headerHeight)

        // Background strip
        let fillColor = UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        fillColor.setFill()
        UIBezierPath(roundedRect: headerRect, cornerRadius: 8).fill()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let titleStr = NSAttributedString(string: metadata.title, attributes: titleAttrs)
        titleStr.draw(at: CGPoint(x: headerRect.minX + 12, y: headerRect.minY + 10))

        // Ticket ID + date
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let subStr = "Ticket #\(metadata.ticketId)  •  \(formatter.string(from: metadata.date))"
        NSAttributedString(string: subStr, attributes: subAttrs)
            .draw(at: CGPoint(x: headerRect.minX + 12, y: headerRect.minY + 36))

        if let tech = metadata.technicianName {
            let techStr = NSAttributedString(
                string: "Technician: \(tech)",
                attributes: subAttrs
            )
            techStr.draw(at: CGPoint(x: headerRect.minX + 12, y: headerRect.minY + 54))
        }
    }

    private static func drawPhoto(page: PhotoReportPage, in rect: CGRect) {
        // Draw image, aspect-fit inside the cell
        let imageRect = aspectFitRect(image: page.image, in: rect)
        page.image.draw(in: imageRect)

        // Border
        UIColor.systemGray4.setStroke()
        let border = UIBezierPath(rect: rect)
        border.lineWidth = 0.5
        border.stroke()

        // Tag badge (top-left)
        if let tag = page.tag {
            let badgeColor: UIColor = tag == "post" ? .systemGreen : .systemOrange
            let badgeRect = CGRect(x: rect.minX + 4, y: rect.minY + 4, width: 36, height: 16)
            badgeColor.setFill()
            UIBezierPath(roundedRect: badgeRect, cornerRadius: 4).fill()
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            NSAttributedString(string: tag.uppercased(), attributes: badgeAttrs)
                .draw(at: CGPoint(x: badgeRect.minX + 4, y: badgeRect.minY + 3))
        }

        // Caption below the cell
        if let caption = page.caption, !caption.isEmpty {
            let captionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            NSAttributedString(string: caption, attributes: captionAttrs)
                .draw(at: CGPoint(x: rect.minX, y: rect.maxY + 4))
        }
    }

    private static func drawFooter(pageNumber: Int, in rect: CGRect) {
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let text = NSAttributedString(string: "Page \(pageNumber)  •  BizarreCRM Photo Report", attributes: footerAttrs)
        text.draw(at: CGPoint(x: margin, y: rect.height - footerHeight))
    }

    private static func aspectFitRect(image: UIImage, in container: CGRect) -> CGRect {
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0 else { return container }
        let scale = min(container.width / iw, container.height / ih)
        let fw = iw * scale
        let fh = ih * scale
        return CGRect(
            x: container.minX + (container.width - fw) / 2,
            y: container.minY + (container.height - fh) / 2,
            width: fw,
            height: fh
        )
    }

    private static func pageIndex(for itemIndex: Int, perRow: Int) -> Int {
        itemIndex / (perRow * 2)
    }

    private static func pdfDocumentInfo(metadata: PhotoReportMetadata) -> [String: Any] {
        [
            kCGPDFContextTitle as String: metadata.title,
            kCGPDFContextCreator as String: "BizarreCRM iOS",
            kCGPDFContextSubject as String: "Ticket #\(metadata.ticketId) Photo Report"
        ]
    }
}
#endif
