import Foundation

// MARK: - ScannedBarcodeEntry

/// A timestamped barcode entry for the in-session scan history.
///
/// Platform-agnostic — no UIKit import — so it's reachable from unit tests
/// running on macOS via `swift test` as well as on device.
public struct ScannedBarcodeEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let value: String
    public let symbology: String
    public let scannedAt: Date

    public init(
        id: UUID = UUID(),
        value: String,
        symbology: String,
        scannedAt: Date = Date()
    ) {
        self.id = id
        self.value = value
        self.symbology = symbology
        self.scannedAt = scannedAt
    }
}
