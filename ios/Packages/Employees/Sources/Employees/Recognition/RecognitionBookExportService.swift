import Foundation
import PDFKit
import SwiftUI
import DesignSystem
import Core

// MARK: - RecognitionBookExportService
//
// §46.7 — End-of-year "recognition book" PDF export.
// Generates a PDF of all received shoutouts for the calendar year,
// formatted as a shareable document for the employee's HR file or
// personal keepsake.
//
// The export is on-device only; no data is sent to a third-party service
// (§32 sovereignty).

public enum RecognitionBookExportService {

    // MARK: - Public API

    /// Generate a PDF for the employee's received shoutouts.
    ///
    /// - Parameters:
    ///   - shoutouts: All shoutouts received by the employee (filtered by year if desired).
    ///   - employeeName: Display name for the cover page.
    ///   - year: Calendar year label (e.g. "2026").
    /// - Returns: `Data` containing the generated PDF bytes, or throws on failure.
    public static func generatePDF(
        shoutouts: [RecognitionShoutout],
        employeeName: String,
        year: String
    ) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            // MARK: Cover page
            ctx.beginPage()
            drawCover(in: pageRect, employeeName: employeeName, year: year, count: shoutouts.count)

            // MARK: Shoutout pages (4 per page)
            let chunked = stride(from: 0, to: shoutouts.count, by: 4).map {
                Array(shoutouts[$0..<min($0 + 4, shoutouts.count)])
            }
            for chunk in chunked {
                ctx.beginPage()
                drawShoutoutPage(in: pageRect, shoutouts: chunk)
            }
        }
        return data
    }

    // MARK: - Cover page

    private static func drawCover(in rect: CGRect, employeeName: String, year: String, count: Int) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.systemOrange
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: UIColor.label
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]

        NSString(string: "Recognition Book").draw(
            at: CGPoint(x: 60, y: 120),
            withAttributes: titleAttrs
        )
        NSString(string: "\(employeeName) — \(year)").draw(
            at: CGPoint(x: 60, y: 168),
            withAttributes: subtitleAttrs
        )
        NSString(string: "\(count) shoutout\(count == 1 ? "" : "s") received this year").draw(
            at: CGPoint(x: 60, y: 210),
            withAttributes: metaAttrs
        )

        // Decorative rule
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 60, y: 245))
        path.addLine(to: CGPoint(x: rect.width - 60, y: 245))
        UIColor.systemOrange.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    // MARK: - Shoutout page

    private static func drawShoutoutPage(in rect: CGRect, shoutouts: [RecognitionShoutout]) {
        let cardHeight: CGFloat = 160
        let margin: CGFloat = 60
        let cardWidth = rect.width - margin * 2

        for (i, s) in shoutouts.enumerated() {
            let y = CGFloat(i) * (cardHeight + 20) + 60
            let cardRect = CGRect(x: margin, y: y, width: cardWidth, height: cardHeight)

            // Card background
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 8)
            UIColor.systemGroupedBackground.setFill()
            cardPath.fill()

            // Category label
            let catAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.systemOrange
            ]
            NSString(string: s.category.displayName.uppercased()).draw(
                at: CGPoint(x: margin + 16, y: y + 16),
                withAttributes: catAttrs
            )

            // From
            if let from = s.fromDisplayName {
                let fromAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                NSString(string: "from \(from)").draw(
                    at: CGPoint(x: margin + 16, y: y + 36),
                    withAttributes: fromAttrs
                )
            }

            // Message body
            let msgAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.label
            ]
            let msgRect = CGRect(x: margin + 16, y: y + 58, width: cardWidth - 32, height: cardHeight - 74)
            NSString(string: s.message).draw(in: msgRect, withAttributes: msgAttrs)
        }
    }
}

// MARK: - RecognitionBookButton

/// Toolbar button that generates + shares the recognition book PDF.
public struct RecognitionBookButton: View {
    let shoutouts: [RecognitionShoutout]
    let employeeName: String
    let year: String

    @State private var pdfURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    public init(shoutouts: [RecognitionShoutout], employeeName: String, year: String = "\(Calendar.current.component(.year, from: Date()))") {
        self.shoutouts = shoutouts
        self.employeeName = employeeName
        self.year = year
    }

    public var body: some View {
        Button {
            generate()
        } label: {
            Label("Export Recognition Book", systemImage: "doc.richtext")
        }
        .accessibilityLabel("Export end-of-year recognition book as PDF")
        .alert("Export Failed", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func generate() {
        do {
            let data = try RecognitionBookExportService.generatePDF(
                shoutouts: shoutouts,
                employeeName: employeeName,
                year: year
            )
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("RecognitionBook-\(year)-\(employeeName).pdf")
            try data.write(to: tmp)
            pdfURL = tmp
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
