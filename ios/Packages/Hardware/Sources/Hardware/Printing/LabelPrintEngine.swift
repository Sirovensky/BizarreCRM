#if canImport(UIKit)
import UIKit
import Foundation
import Core

// MARK: - Label Render Engine
//
// Generates a PNG or PDF from `LabelPayload` using UIGraphicsImageRenderer
// and dispatches via AirPrint (UIPrintInteractionController).
//
// SDK-specific paths (Zebra ZSDK / Brother SDK) are deferred.
// TODO §17: Integrate Zebra ZSDK (ZebraLink) for direct Zebra ZSB-DP12 support.
// TODO §17: Integrate Brother SDK for QL-820NWB direct BT/Wi-Fi path.

@MainActor
public final class LabelPrintEngine: PrintEngine {

    // MARK: PrintEngine – discover

    /// Label printing is dispatched through AirPrint; no separate discovery.
    /// Returns empty array — caller should use `AirPrintEngine.presentPicker`.
    public func discover() async throws -> [Printer] { [] }

    // MARK: PrintEngine – print

    public func print(_ job: PrintJob, on printer: Printer) async throws {
        switch job.payload {
        case .label(let payload):
            let pdfURL = try renderLabel(payload)
            try await airPrint(pdfURL: pdfURL, on: printer)
        case .ticketTag(let payload):
            let pdfURL = try renderTicketTag(payload)
            try await airPrint(pdfURL: pdfURL, on: printer)
        default:
            throw PrintEngineError.unsupportedJobKind(job.kind)
        }
    }

    // MARK: - Label renderer

    /// Renders a LabelPayload to a temporary PDF file.
    /// Layout:
    ///   Row 1 (bold): ticketNumber
    ///   Row 2: customerName
    ///   Row 3 (italic): deviceSummary
    ///   Row 4 (small): dateReceived
    ///   Right side: QR code
    public func renderLabel(_ payload: LabelPayload) throws -> URL {
        let size = payload.size.pointSize
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))

        let data = renderer.pdfData { context in
            context.beginPage()
            Self.drawLabelContent(payload: payload, in: CGRect(origin: .zero, size: size))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("label-\(payload.ticketNumber)-\(UUID().uuidString).pdf")
        try data.write(to: tempURL)
        AppLog.hardware.info("LabelPrintEngine: rendered label PDF to \(tempURL.lastPathComponent, privacy: .public)")
        return tempURL
    }

    /// Renders a TicketTagPayload to a temporary PDF file.
    public func renderTicketTag(_ payload: TicketTagPayload) throws -> URL {
        let size = CGSize(width: 144, height: 72) // 2"x1" default for hang tag
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))

        let data = renderer.pdfData { context in
            context.beginPage()
            Self.drawTicketTagContent(payload: payload, in: CGRect(origin: .zero, size: size))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tag-\(payload.ticketNumber)-\(UUID().uuidString).pdf")
        try data.write(to: tempURL)
        return tempURL
    }

    // MARK: - Drawing helpers (static so they're callable from tests)

    static func drawLabelContent(payload: LabelPayload, in rect: CGRect) {
        let padding: CGFloat = 4
        let qrSize = min(rect.height - padding * 2, 60)
        let textWidth = rect.width - qrSize - padding * 3

        // QR code image (right side)
        if let qrImage = generateQRCode(payload.qrContent, size: CGSize(width: qrSize, height: qrSize)) {
            let qrRect = CGRect(
                x: rect.maxX - qrSize - padding,
                y: rect.minY + padding,
                width: qrSize,
                height: qrSize
            )
            qrImage.draw(in: qrRect)
        }

        // Text block (left side)
        var y = rect.minY + padding
        let ticketAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.black
        ]
        let deviceAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 8),
            .foregroundColor: UIColor.darkGray
        ]
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7),
            .foregroundColor: UIColor.darkGray
        ]

        func drawLine(_ text: String, attrs: [NSAttributedString.Key: Any], maxWidth: CGFloat) -> CGFloat {
            let str = NSAttributedString(string: text, attributes: attrs)
            let size = str.boundingRect(with: CGSize(width: maxWidth, height: .infinity),
                                        options: .usesLineFragmentOrigin, context: nil).size
            str.draw(in: CGRect(x: rect.minX + padding, y: y, width: maxWidth, height: size.height))
            return size.height + 1
        }

        y += drawLine(payload.ticketNumber, attrs: ticketAttrs, maxWidth: textWidth)
        y += drawLine(payload.customerName, attrs: nameAttrs, maxWidth: textWidth)
        y += drawLine(payload.deviceSummary, attrs: deviceAttrs, maxWidth: textWidth)

        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        y += drawLine(df.string(from: payload.dateReceived), attrs: dateAttrs, maxWidth: textWidth)
    }

    static func drawTicketTagContent(payload: TicketTagPayload, in rect: CGRect) {
        let padding: CGFloat = 3
        let qrSize: CGFloat = min(rect.height - padding * 2, 50)
        let textWidth = rect.width - qrSize - padding * 3

        if let qrImage = generateQRCode(payload.qrContent, size: CGSize(width: qrSize, height: qrSize)) {
            qrImage.draw(in: CGRect(x: rect.maxX - qrSize - padding,
                                    y: rect.minY + padding,
                                    width: qrSize, height: qrSize))
        }

        var y = rect.minY + padding
        let boldAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 10)]
        let smallAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8)]

        func drawLine(_ text: String, attrs: [NSAttributedString.Key: Any]) -> CGFloat {
            let str = NSAttributedString(string: text, attributes: attrs)
            let sz = str.boundingRect(with: CGSize(width: textWidth, height: .infinity),
                                      options: .usesLineFragmentOrigin, context: nil).size
            str.draw(in: CGRect(x: rect.minX + padding, y: y, width: textWidth, height: sz.height))
            return sz.height + 1
        }

        y += drawLine(payload.ticketNumber, attrs: boldAttrs)
        y += drawLine(payload.customerName, attrs: smallAttrs)
        y += drawLine(payload.deviceModel, attrs: smallAttrs)

        if let promised = payload.promisedBy {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            y += drawLine("Due: \(df.string(from: promised))", attrs: smallAttrs)
        }
    }

    // MARK: - QR Code generation

    /// Generates a UIImage containing a QR code using CoreImage.
    public static func generateQRCode(_ content: String, size: CGSize) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = content.data(using: .utf8) ?? Data()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        let scaleX = size.width / outputImage.extent.width
        let scaleY = size.height / outputImage.extent.height
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - AirPrint dispatch

    private func airPrint(pdfURL: URL, on printer: Printer) async throws {
        guard case .airPrint(let printerURL) = printer.connection else {
            throw PrintEngineError.printerNotReachable(printer.id)
        }

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .photo
        printInfo.jobName = "BizarreCRM Label"

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdfURL

        let uiPrinter = UIPrinter(url: printerURL)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controller.print(to: uiPrinter) { _, completed, error in
                if let error = error {
                    continuation.resume(throwing: PrintEngineError.sendFailed(error.localizedDescription))
                } else if completed {
                    AppLog.hardware.info("LabelPrintEngine: label sent to printer")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrintEngineError.cancelled)
                }
            }
        }
    }
}

#endif
