#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem
import Networking

// §4.2 — Share PDF / AirPrint pipeline.
//
// WorkOrderTicketView → ImageRenderer → local PDF file (never a web URL).
// Hand the file URL to:
//   - Share sheet: UIActivityViewController (share via email = PDF attached;
//     share via SMS = public tracking link via §53 — that is handled at the call-site).
//   - AirPrint: UIPrintInteractionController.
//
// Fully offline-capable: no network call required.

// MARK: - Work order renderable model

/// All data needed to render a printable work-order PDF for a ticket.
public struct WorkOrderModel: Sendable {
    public let orderId: String
    public let customerName: String
    public let customerPhone: String?
    public let customerEmail: String?
    public let deviceLines: [DeviceLine]
    public let notes: String?
    public let statusName: String?
    public let totalFormatted: String
    public let dateCreated: String
    public let technicianName: String?

    public struct DeviceLine: Sendable {
        public let name: String
        public let imei: String?
        public let serial: String?
        public let service: String?
        public let price: String
    }

    public init(
        orderId: String,
        customerName: String,
        customerPhone: String?,
        customerEmail: String?,
        deviceLines: [DeviceLine],
        notes: String?,
        statusName: String?,
        totalFormatted: String,
        dateCreated: String,
        technicianName: String?
    ) {
        self.orderId = orderId
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.customerEmail = customerEmail
        self.deviceLines = deviceLines
        self.notes = notes
        self.statusName = statusName
        self.totalFormatted = totalFormatted
        self.dateCreated = dateCreated
        self.technicianName = technicianName
    }

    /// Build a model from `TicketDetail`.
    public static func from(_ detail: TicketDetail) -> WorkOrderModel {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        let totalStr = fmt.string(from: NSNumber(value: detail.total ?? 0)) ?? "$0.00"

        let customer = detail.customer
        let deviceLines = detail.devices.map { d in
            DeviceLine(
                name: d.displayName,
                imei: d.imei,
                serial: d.serial,
                service: nil,
                price: "$0.00"
            )
        }

        return WorkOrderModel(
            orderId: detail.orderId,
            customerName: customer?.displayName ?? "Unknown",
            customerPhone: customer?.phone,
            customerEmail: customer?.email,
            deviceLines: deviceLines,
            notes: detail.notes.first(where: { $0.type == "internal" })?.content,
            statusName: detail.status?.name,
            totalFormatted: totalStr,
            dateCreated: detail.createdAt ?? "",
            technicianName: nil
        )
    }
}

// MARK: - Renderable work order view

/// SwiftUI view that renders a clean, printable work-order layout.
/// Used with `ImageRenderer` to produce a local PDF.
public struct WorkOrderTicketView: View {
    let model: WorkOrderModel

    public init(model: WorkOrderModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORK ORDER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.gray)
                    Text("# \(model.orderId)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let status = model.statusName {
                        Text(status.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                    Text(model.dateCreated)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
            }
            .padding(.bottom, 4)

            Divider()

            // Customer
            Group {
                Text("CUSTOMER")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.gray)
                Text(model.customerName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                if let phone = model.customerPhone {
                    Text(phone)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(uiColor: .darkGray))
                }
                if let email = model.customerEmail {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(uiColor: .darkGray))
                }
            }
            .padding(.bottom, 4)

            Divider()

            // Devices
            Text("DEVICES & SERVICES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)

            ForEach(Array(model.deviceLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                        if let imei = line.imei, !imei.isEmpty {
                            Text("IMEI: \(imei)")
                                .font(.system(size: 11))
                                .foregroundStyle(.gray)
                        }
                        if let serial = line.serial, !serial.isEmpty {
                            Text("S/N: \(serial)")
                                .font(.system(size: 11))
                                .foregroundStyle(.gray)
                        }
                        if let service = line.service, !service.isEmpty {
                            Text(service)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(uiColor: .darkGray))
                        }
                    }
                    Spacer()
                    Text(line.price)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .padding(.vertical, 4)
                Divider().opacity(0.4)
            }

            // Totals
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text("Total")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                        Text(model.totalFormatted)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(.top, 4)

            // Notes
            if let notes = model.notes, !notes.isEmpty {
                Divider()
                Text("NOTES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.gray)
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(uiColor: .darkGray))
            }

            Spacer()

            // Footer
            Divider()
            Text("Thank you for your business.")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
        .frame(width: 612, height: 792)  // US Letter in points
        .background(Color.white)
    }
}

// MARK: - PDF rendering service

/// §4.2 — Renders a work-order PDF locally (no network) and returns a file URL
/// in the app's temporary directory. Fully offline-capable.
@MainActor
public struct TicketSharePrintService {

    public init() {}

    /// Render a `WorkOrderModel` to a local PDF file and return the URL.
    public func renderPDF(model: WorkOrderModel) throws -> URL {
        let renderer = ImageRenderer(content: WorkOrderTicketView(model: model))
        renderer.scale = UIScreen.main.scale

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "WorkOrder-\(model.orderId).pdf"
        let fileURL = tempDir.appendingPathComponent(fileName)

        guard renderer.uiImage != nil else {
            throw RenderError.renderFailed
        }

        // Render to PDF via UIGraphicsPDFRenderer (US Letter)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            if let img = renderer.uiImage {
                img.draw(in: pageRect)
            }
        }
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// Present the AirPrint dialog for a work order.
    public func airPrint(model: WorkOrderModel, from scene: UIWindowScene?) {
        guard let pdfURL = try? renderPDF(model: model) else { return }
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "Ticket \(model.orderId)"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdfURL
        if let scene {
            let windows = scene.windows
            let sourceView = windows.first?.rootViewController?.view
            controller.present(animated: true) { _, _, _ in }
            _ = sourceView  // suppress unused-variable warning
        } else {
            controller.present(animated: true) { _, _, _ in }
        }
    }

    // MARK: - Errors

    public enum RenderError: Error {
        case renderFailed
    }
}

// MARK: - SwiftUI button helpers

/// §4.2 — "Print" toolbar button that triggers AirPrint.
public struct TicketAirPrintButton: View {
    let model: WorkOrderModel
    let service: TicketSharePrintService

    public init(model: WorkOrderModel) {
        self.model = model
        self.service = TicketSharePrintService()
    }

    public var body: some View {
        Button {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
            service.airPrint(model: model, from: scene)
        } label: {
            Label("Print Work Order", systemImage: "printer")
        }
        .accessibilityLabel("Print work order via AirPrint")
    }
}

/// §4.2 — "Share PDF" button that presents a share sheet with the local PDF file.
public struct TicketSharePDFButton: View {
    let model: WorkOrderModel
    @State private var pdfURL: URL?
    @State private var showShareSheet = false

    public init(model: WorkOrderModel) {
        self.model = model
    }

    public var body: some View {
        Button {
            let svc = TicketSharePrintService()
            if let url = try? svc.renderPDF(model: model) {
                pdfURL = url
                showShareSheet = true
            }
        } label: {
            Label("Share as PDF", systemImage: "doc.richtext")
        }
        .accessibilityLabel("Share work order as PDF")
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                TicketPDFShareSheet(url: url)
            }
        }
    }
}

private struct TicketPDFShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
