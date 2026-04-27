#if canImport(SwiftUI)
import SwiftUI
import Core

// §17.4 Test print page — rendered locally via the same pipeline as receipts.
//
// Shown by Settings "Print test page" button (in `PrinterSettingsView`).
// Renders: logo placeholder + shop name + current time + printer capability matrix.
// Same `@Environment(\.printMedium)` adaptation as all other document views.

// MARK: - TestPageModel

public struct TestPageModel: Sendable {
    public let tenantName: String
    public let printerName: String
    public let printerModel: String
    public let connection: String
    public let printedAt: Date
    public let supportedKinds: [String]

    public init(
        tenantName: String,
        printerName: String,
        printerModel: String,
        connection: String,
        printedAt: Date = Date(),
        supportedKinds: [String] = ["Receipt", "Gift Receipt", "Label", "Z-Report"]
    ) {
        self.tenantName = tenantName
        self.printerName = printerName
        self.printerModel = printerModel
        self.connection = connection
        self.printedAt = printedAt
        self.supportedKinds = supportedKinds
    }
}

// MARK: - TestPageView

/// Printable test page. Same source backs print + in-app preview.
/// Not using Liquid Glass — this is a print-target document (content, not chrome).
public struct TestPageView: View {

    public let model: TestPageModel
    @Environment(\.printMedium) private var medium

    public init(model: TestPageModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            infoBlock
            divider
            capabilityMatrix
            divider
            footer
        }
        .frame(width: medium.contentWidth)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 2) {
            Image(systemName: "printer.fill")
                .font(.system(size: medium == .thermal80mm || medium == .thermal58mm ? 24 : 40))
                .accessibilityHidden(true)
            Text("PRINTER TEST PAGE")
                .font(medium.headerFont)
                .accessibilityAddTraits(.isHeader)
            Text(model.tenantName)
                .font(medium.bodyFont)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Info block

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            labelValue("Printer:", model.printerName)
            labelValue("Model:", model.printerModel)
            labelValue("Connection:", model.connection)
            labelValue("Printed at:", model.printedAt.formatted(.dateTime.month().day().year().hour().minute().second()))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Capability matrix

    private var capabilityMatrix: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Supported Document Types")
                .font(medium.bodyFont.bold())
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.supportedKinds, id: \.self) { kind in
                HStack(spacing: 4) {
                    Text("✓")
                        .font(medium.bodyFont)
                        .accessibilityHidden(true)
                    Text(kind)
                        .font(medium.bodyFont)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("BizarreCRM — If you can read this, the printer is working correctly.")
            .font(medium.captionFont)
            .foregroundStyle(Color.gray)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
    }

    // MARK: - Label-value helper

    private func labelValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(medium.captionFont)
                .foregroundStyle(Color.gray)
                .frame(minWidth: 80, alignment: .leading)
            Text(value)
                .font(medium.bodyFont)
        }
    }
}

#endif
