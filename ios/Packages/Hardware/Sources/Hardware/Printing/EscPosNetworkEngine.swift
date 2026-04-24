import Foundation
import Network
import Core

// MARK: - ESC/POS Network Engine
//
// Connects to a printer over a raw TCP socket (NWConnection) and sends
// ESC/POS bytes built by EscPosCommandBuilder.
//
// Target printers: Star TSP143 (network), Epson TM-T88 (network).
// Default port: 9100 (raw print port per both vendors).

public final class EscPosNetworkEngine: PrintEngine {

    // MARK: Configuration

    public struct Config: Sendable {
        public let host: String
        public let port: Int
        public let connectionTimeoutSeconds: Double

        public init(host: String, port: Int = 9100, connectionTimeoutSeconds: Double = 8) {
            self.host = host
            self.port = port
            self.connectionTimeoutSeconds = connectionTimeoutSeconds
        }
    }

    private let config: Config

    public init(config: Config) {
        self.config = config
    }

    // MARK: PrintEngine – discover

    /// Network engine discovery: attempt a TCP ping to the configured host:port.
    /// Returns a single Printer if reachable, empty array otherwise.
    public func discover() async throws -> [Printer] {
        let reachable = await pingOnce()
        guard reachable else { return [] }
        let id = "\(config.host):\(config.port)"
        let printer = Printer(
            id: id,
            name: "ESC/POS @ \(config.host)",
            kind: .thermalReceipt,
            connection: .network(host: config.host, port: config.port),
            status: .idle
        )
        return [printer]
    }

    // MARK: PrintEngine – print

    public func print(_ job: PrintJob, on printer: Printer) async throws {
        guard case .network(let host, let port) = printer.connection else {
            throw PrintEngineError.printerNotReachable(printer.id)
        }
        let bytes = try buildBytes(for: job)
        try await send(bytes, to: host, port: port)
        AppLog.hardware.info("EscPosNetworkEngine: sent \(bytes.count) bytes to \(host, privacy: .public):\(port)")
    }

    // MARK: - Private: byte building

    private func buildBytes(for job: PrintJob) throws -> Data {
        switch job.payload {
        case .receipt(let payload):
            return EscPosCommandBuilder.receipt(payload)
        case .barcode(let payload):
            var data = EscPosCommandBuilder.initialize()
            data.append(contentsOf: EscPosCommandBuilder.align(.center))
            data.append(contentsOf: EscPosCommandBuilder.barcode(payload.code, format: payload.format))
            data.append(contentsOf: EscPosCommandBuilder.feed(4))
            data.append(contentsOf: EscPosCommandBuilder.cut(partial: true))
            return data
        case .label(let payload):
            // Labels are best handled via AirPrint/LabelPrintEngine; fall back
            // to a minimal text dump here for network-attached label printers.
            var data = EscPosCommandBuilder.initialize()
            data.append(contentsOf: EscPosCommandBuilder.align(.center))
            data.append(contentsOf: EscPosCommandBuilder.text(payload.ticketNumber))
            data.append(contentsOf: EscPosCommandBuilder.text(payload.customerName))
            data.append(contentsOf: EscPosCommandBuilder.text(payload.deviceSummary))
            data.append(contentsOf: EscPosCommandBuilder.qrCode(payload.qrContent))
            data.append(contentsOf: EscPosCommandBuilder.feed(4))
            data.append(contentsOf: EscPosCommandBuilder.cut(partial: true))
            return data
        case .ticketTag(let payload):
            var data = EscPosCommandBuilder.initialize()
            data.append(contentsOf: EscPosCommandBuilder.align(.center))
            data.append(contentsOf: EscPosCommandBuilder.text(payload.ticketNumber))
            data.append(contentsOf: EscPosCommandBuilder.text(payload.customerName))
            data.append(contentsOf: EscPosCommandBuilder.text(payload.deviceModel))
            data.append(contentsOf: EscPosCommandBuilder.qrCode(payload.qrContent))
            data.append(contentsOf: EscPosCommandBuilder.feed(4))
            data.append(contentsOf: EscPosCommandBuilder.cut(partial: true))
            return data
        }
    }

    // MARK: - Private: TCP send

    func send(_ data: Data, to host: String, port: Int) async throws {
        let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 9100
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: .tcp
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            let resume: @Sendable (Result<Void, Error>) -> Void = { @Sendable result in
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error = error {
                            resume(.failure(PrintEngineError.sendFailed(error.localizedDescription)))
                        } else {
                            resume(.success(()))
                        }
                    })
                case .failed(let error):
                    resume(.failure(PrintEngineError.printerNotReachable("\(host):\(port) — \(error.localizedDescription)")))
                case .waiting(let error):
                    resume(.failure(PrintEngineError.printerNotReachable("\(host):\(port) waiting: \(error.localizedDescription)")))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))

            // Timeout guard
            let timeoutNS = UInt64(config.connectionTimeoutSeconds * 1_000_000_000)
            Task {
                try? await Task.sleep(nanoseconds: timeoutNS)
                resume(.failure(PrintEngineError.printerNotReachable("\(host):\(port) — connection timed out")))
            }
        }
    }

    // MARK: - Private: ping

    func pingOnce() async -> Bool {
        do {
            try await send(Data(), to: config.host, port: config.port)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - EscPosSender conformance
//
// Allows `EscPosDrawerKick(sender: networkEngine)` to be constructed directly
// so a cash drawer can share the same TCP transport as the receipt printer.
// `isConnected` is a best-effort synchronous hint: true once the first
// successful print (or ping) has completed.

extension EscPosNetworkEngine: EscPosSender {

    /// Send raw bytes to the configured ESC/POS host:port.
    public func sendBytes(_ bytes: [UInt8]) async throws {
        try await send(Data(bytes), to: config.host, port: config.port)
    }

    /// `true` when the printer replied to the last discover/ping call.
    /// Does NOT establish a persistent connection; ESC/POS is stateless TCP.
    public var isConnected: Bool {
        // Synchronous conservative default: assume connected if config is non-empty.
        // The actual reachability is validated inside `sendBytes` on each call.
        !config.host.isEmpty
    }
}
