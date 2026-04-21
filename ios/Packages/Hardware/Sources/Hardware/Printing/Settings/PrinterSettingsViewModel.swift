#if canImport(UIKit)
import Foundation
import Observation
import Core

// MARK: - Persisted Printer Record
//
// Lightweight Codable wrapper around `Printer` for UserDefaults persistence.
// TODO §17: migrate to GRDB when persistence layer lands.

public struct PersistedPrinter: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: PrinterKind
    public let connection: PrinterConnection
    public var isDefaultReceipt: Bool
    public var isDefaultLabel: Bool

    public init(
        id: String,
        name: String,
        kind: PrinterKind,
        connection: PrinterConnection,
        isDefaultReceipt: Bool = false,
        isDefaultLabel: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.connection = connection
        self.isDefaultReceipt = isDefaultReceipt
        self.isDefaultLabel = isDefaultLabel
    }

    public var asPrinter: Printer {
        Printer(id: id, name: name, kind: kind, connection: connection)
    }
}

// MARK: - ViewModel

@Observable
@MainActor
public final class PrinterSettingsViewModel {

    // MARK: Published state

    public private(set) var printers: [PersistedPrinter] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    // Network ESC/POS add-form fields (bound from view)
    public var newPrinterHost: String = ""
    public var newPrinterPort: String = "9100"
    public var newPrinterNickname: String = ""

    // MARK: Private

    private static let defaultsKey = "com.bizarrecrm.hardware.printers"
    private let airPrintEngine: AirPrintEngine

    public init(airPrintEngine: AirPrintEngine = AirPrintEngine()) {
        self.airPrintEngine = airPrintEngine
        load()
    }

    // MARK: - Load / Save

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([PersistedPrinter].self, from: data) else {
            printers = []
            return
        }
        printers = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(printers) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    // MARK: - Add AirPrint (interactive picker)

    /// Present `UIPrinterPickerController`. Must be called from a `UIViewController`.
    public func addAirPrintPrinter(from viewController: UIViewController) async {
        isLoading = true
        defer { isLoading = false }
        guard let printer = await airPrintEngine.presentPicker(from: viewController) else {
            return // user cancelled
        }
        upsert(PersistedPrinter(
            id: printer.id,
            name: printer.name,
            kind: printer.kind,
            connection: printer.connection
        ))
    }

    // MARK: - Add ESC/POS Network printer

    /// Validates the form fields and adds the printer if reachable.
    public func addNetworkPrinter() async {
        let host = newPrinterHost.trimmingCharacters(in: .whitespaces)
        let portInt = Int(newPrinterPort) ?? 9100
        let nickname = newPrinterNickname.trimmingCharacters(in: .whitespaces)

        guard !host.isEmpty else {
            errorMessage = "Host / IP address is required."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let config = EscPosNetworkEngine.Config(host: host, port: portInt, connectionTimeoutSeconds: 5)
        let engine = EscPosNetworkEngine(config: config)

        let discovered = (try? await engine.discover()) ?? []
        guard !discovered.isEmpty else {
            errorMessage = "Could not reach \(host):\(portInt). Check the IP/port and try again."
            return
        }

        let displayName = nickname.isEmpty ? "ESC/POS @ \(host)" : nickname
        let id = "\(host):\(portInt)"
        upsert(PersistedPrinter(
            id: id,
            name: displayName,
            kind: .thermalReceipt,
            connection: .network(host: host, port: portInt)
        ))
        newPrinterHost = ""
        newPrinterPort = "9100"
        newPrinterNickname = ""
    }

    // MARK: - Remove

    public func remove(_ printer: PersistedPrinter) {
        printers.removeAll { $0.id == printer.id }
        save()
    }

    // MARK: - Set as default

    public func setAsDefaultReceipt(_ printer: PersistedPrinter) {
        printers = printers.map { p in
            var copy = p
            copy.isDefaultReceipt = p.id == printer.id
            return copy
        }
        save()
    }

    public func setAsDefaultLabel(_ printer: PersistedPrinter) {
        printers = printers.map { p in
            var copy = p
            copy.isDefaultLabel = p.id == printer.id
            return copy
        }
        save()
    }

    // MARK: - Test print

    public func testPrint(_ printer: PersistedPrinter) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let payload = ReceiptPayload(
            tenantName: "Test Printer",
            tenantAddress: "123 Main St",
            tenantPhone: "(555) 000-0000",
            receiptNumber: "TEST-001",
            createdAt: Date(),
            lineItems: [ReceiptPayload.Line(label: "Test item", value: "$1.00")],
            subtotalCents: 100,
            taxCents: 8,
            tipCents: 0,
            totalCents: 108,
            paymentTender: "Cash",
            cashierName: "System",
            footerMessage: "Hardware test print — BizarreCRM",
            qrContent: nil
        )

        let job = PrintJob(kind: .receipt, payload: .receipt(payload))

        do {
            switch printer.connection {
            case .network(let host, let port):
                let config = EscPosNetworkEngine.Config(host: host, port: port)
                let engine = EscPosNetworkEngine(config: config)
                try await engine.print(job, on: printer.asPrinter)
            case .airPrint:
                let engine = AirPrintEngine()
                try await engine.print(job, on: printer.asPrinter)
            case .bluetoothMFi:
                // MFi path deferred — TODO §17 MFi SDK integration
                errorMessage = "Bluetooth MFi printing not yet available. Use AirPrint or ESC/POS network."
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.hardware.error("PrinterSettingsViewModel test print failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Convenience: default printers

    public var defaultReceiptPrinter: PersistedPrinter? {
        printers.first { $0.isDefaultReceipt }
    }

    public var defaultLabelPrinter: PersistedPrinter? {
        printers.first { $0.isDefaultLabel }
    }

    // MARK: - Private: upsert (immutable update)

    private func upsert(_ printer: PersistedPrinter) {
        if let idx = printers.firstIndex(where: { $0.id == printer.id }) {
            printers[idx] = printer
        } else {
            printers.append(printer)
        }
        save()
    }
}

#endif
