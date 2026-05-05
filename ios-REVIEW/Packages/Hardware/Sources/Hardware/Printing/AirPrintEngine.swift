#if canImport(UIKit)
import UIKit
import Foundation
import Core

// MARK: - AirPrint Engine
//
// Uses UIPrintInteractionController + UIPrinterPickerController.
//
// Discovery:
//   Interactive path  — present UIPrinterPickerController so the user picks
//                       a printer; the choice is cached in UserDefaults.
//   Headless path     — use the previously cached printer URL directly.
//                       Falls back to noPrinterConfigured if cache is empty.
//
// Printing:
//   Renders payload → temp PDF file → hands file URL to
//   UIPrintInteractionController. Never passes a remote URL (Android lesson §17.4).

@MainActor
public final class AirPrintEngine: NSObject, PrintEngine {

    // MARK: Persistence keys

    private static let defaultsKey = "com.bizarrecrm.hardware.airprint.defaultPrinterURL"

    // MARK: PrintEngine – discover

    public func discover() async throws -> [Printer] {
        guard let urlString = UserDefaults.standard.string(forKey: Self.defaultsKey),
              let url = URL(string: urlString) else {
            return []
        }
        let printer = Printer(
            id: urlString,
            name: url.host ?? urlString,
            kind: .thermalReceipt,
            connection: .airPrint(url: url),
            status: .idle
        )
        return [printer]
    }

    // MARK: PrintEngine – print

    public func print(_ job: PrintJob, on printer: Printer) async throws {
        guard case .airPrint(let printerURL) = printer.connection else {
            throw PrintEngineError.printerNotReachable(printer.id)
        }
        let pdfURL = try renderToPDF(job)
        try await sendViaAirPrint(pdfURL: pdfURL, printerURL: printerURL)
    }

    // MARK: Picker (interactive – call from Settings)

    /// Present UIPrinterPickerController. On selection, cache the printer URL
    /// in UserDefaults so headless prints can reuse it.
    ///
    /// - Parameter viewController: The presenting view controller.
    /// - Returns: The selected `Printer`, or nil if the user cancelled.
    public func presentPicker(from viewController: UIViewController) async -> Printer? {
        await withCheckedContinuation { continuation in
            let picker = UIPrinterPickerController(initiallySelectedPrinter: nil)
            picker.present(animated: true) { [weak self] pickerController, userDidSelect, error in
                guard let self, userDidSelect, let selected = pickerController.selectedPrinter else {
                    continuation.resume(returning: nil)
                    return
                }
                let urlString = selected.url.absoluteString
                UserDefaults.standard.set(urlString, forKey: Self.defaultsKey)
                AppLog.hardware.info("AirPrintEngine: cached printer \(urlString, privacy: .public)")
                let printer = Printer(
                    id: urlString,
                    name: selected.displayName,
                    kind: .thermalReceipt,
                    connection: .airPrint(url: selected.url),
                    status: .idle
                )
                continuation.resume(returning: printer)
            }
        }
    }

    /// Clear the cached printer.
    public func clearCachedPrinter() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - Private helpers

    private func renderToPDF(_ job: PrintJob) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 226, height: 792))
        let data = renderer.pdfData { context in
            context.beginPage()
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .paragraphStyle: paragraphStyle
            ]
            let body = jobBodyText(job)
            let rect = CGRect(x: 8, y: 8, width: 210, height: 776)
            body.draw(in: rect, withAttributes: attrs)
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("print-\(job.id.uuidString).pdf")
        try data.write(to: tempURL)
        return tempURL
    }

    private func jobBodyText(_ job: PrintJob) -> String {
        switch job.payload {
        case .receipt(let payload):
            return receiptText(payload)
        case .label(let payload):
            return "LABEL\n\(payload.ticketNumber)\n\(payload.customerName)\n\(payload.deviceSummary)"
        case .ticketTag(let payload):
            return "TAG\n\(payload.ticketNumber)\n\(payload.customerName)\n\(payload.deviceModel)"
        case .barcode(let payload):
            return "BARCODE\n\(payload.code)\n[\(payload.format.rawValue)]"
        }
    }

    private func receiptText(_ p: ReceiptPayload) -> String {
        var lines: [String] = []
        lines.append(p.tenantName)
        lines.append(p.tenantAddress)
        lines.append(p.tenantPhone)
        lines.append(String(repeating: "-", count: 32))
        lines.append("Receipt: \(p.receiptNumber)")
        lines.append(String(repeating: "-", count: 32))
        for item in p.lineItems {
            let pad = max(1, 32 - item.label.count - item.value.count)
            lines.append(item.label + String(repeating: " ", count: pad) + item.value)
        }
        lines.append(String(repeating: "-", count: 32))
        lines.append("TOTAL: \(Self.formatCents(p.totalCents))")
        lines.append("Tender: \(p.paymentTender)")
        if let footer = p.footerMessage { lines.append(footer) }
        return lines.joined(separator: "\n")
    }

    private static func formatCents(_ cents: Int) -> String {
        let dollars = abs(cents) / 100
        let pennies = abs(cents) % 100
        let sign = cents < 0 ? "-" : ""
        return "\(sign)$\(dollars).\(String(format: "%02d", pennies))"
    }

    @MainActor
    private func sendViaAirPrint(pdfURL: URL, printerURL: URL) async throws {
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "BizarreCRM Receipt"

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdfURL

        let uiPrinter = UIPrinter(url: printerURL)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controller.print(to: uiPrinter) { _, completed, error in
                if let error = error {
                    continuation.resume(throwing: PrintEngineError.sendFailed(error.localizedDescription))
                } else if completed {
                    AppLog.hardware.info("AirPrintEngine: print completed to \(printerURL.absoluteString, privacy: .public)")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrintEngineError.cancelled)
                }
            }
        }
    }
}

#endif
