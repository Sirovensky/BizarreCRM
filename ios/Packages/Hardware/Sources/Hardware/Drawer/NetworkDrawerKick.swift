import Foundation
import Core

// MARK: - NetworkDrawerKick

/// Direct TCP drawer kick for rare setups where the cash drawer has its own
/// network interface (e.g. APG ethernet drawer controllers).
///
/// Most installations should prefer `EscPosDrawerKick` which piggybacks on
/// the receipt printer's RJ-11 port. Use `NetworkDrawerKick` only when the
/// drawer is a standalone networked unit with no printer attachment.
///
/// Protocol: sends the 5-byte ESC/POS kick sequence over a plain TCP socket
/// to the drawer controller's IP:port. Some controllers accept this directly;
/// others expose a proprietary HTTP API — check the controller manual.
public final class NetworkDrawerKick: CashDrawer, @unchecked Sendable {

    // MARK: - Configuration

    public struct Config: Sendable {
        public let host: String
        public let port: UInt16
        public let timeoutSeconds: Double

        public init(host: String, port: UInt16 = 9100, timeoutSeconds: Double = 5.0) {
            self.host = host
            self.port = port
            self.timeoutSeconds = timeoutSeconds
        }
    }

    // MARK: - State

    private let config: Config
    private var _isConnected: Bool = false

    // MARK: - Init

    public init(config: Config) {
        self.config = config
    }

    // MARK: - CashDrawer

    public var isConnected: Bool { _isConnected }

    public func open() async throws {
        guard !config.host.isEmpty else {
            throw CashDrawerError.kickFailed("No host configured")
        }
        let logMsg = "NetworkDrawerKick: opening drawer at \(config.host):\(config.port)"
        AppLog.hardware.info("\(logMsg)")
        let command = EscPosDrawerKick.kickCommand
        do {
            try await sendTCP(bytes: command)
            _isConnected = true
        } catch {
            _isConnected = false
            throw CashDrawerError.kickFailed(error.localizedDescription)
        }
    }

    // MARK: - Private TCP send

    private func sendTCP(bytes: [UInt8]) async throws {
        let host = config.host
        let port = Int(config.port)
        let timeoutSeconds = config.timeoutSeconds

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.bizarrecrm.networkdrawer", qos: .userInitiated)

            var inputStream: InputStream?
            var outputStream: OutputStream?

            Stream.getStreamsToHost(
                withName: host,
                port: port,
                inputStream: &inputStream,
                outputStream: &outputStream
            )

            guard let out = outputStream else {
                continuation.resume(throwing: CashDrawerError.kickFailed("Could not create stream to \(host):\(port)"))
                return
            }

            // Take a local copy to avoid capturing `out` across Sendable boundary.
            let stream = out
            let bytesCopy = bytes

            queue.async {
                stream.open()

                let start = Date()
                while stream.streamStatus != .open {
                    if Date().timeIntervalSince(start) > timeoutSeconds {
                        stream.close()
                        continuation.resume(throwing: CashDrawerError.kickFailed("TCP connect timed out"))
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }

                let bytesWritten = bytesCopy.withUnsafeBytes { ptr -> Int in
                    guard let base = ptr.baseAddress else { return -1 }
                    return stream.write(base.assumingMemoryBound(to: UInt8.self), maxLength: bytesCopy.count)
                }

                stream.close()

                if bytesWritten == bytesCopy.count {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CashDrawerError.kickFailed("Short write: \(bytesWritten) of \(bytesCopy.count) bytes"))
                }
            }
        }
    }
}
