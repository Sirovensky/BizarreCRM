#if canImport(UIKit) && canImport(VisionKit)
import UIKit
import VisionKit
import AVFoundation
import Observation
import Core

// MARK: - ScanMode

/// Controls whether the scanner stops after the first result or keeps scanning.
public enum BarcodeScanMode: Sendable {
    /// Stop scanning immediately after the first accepted barcode.
    case single
    /// Keep scanning continuously until the user dismisses.
    case continuous
}

// MARK: - BarcodeCoordinator

/// @MainActor observable coordinator for ``BarcodeScannerView``.
///
/// Responsibilities:
/// - Checks `DataScannerViewController.isSupported` (iOS 16+; Mac Catalyst returns false).
/// - Handles camera authorization.
/// - Bridges `DataScannerViewControllerDelegate` callbacks into observable state.
/// - De-duplicates rapid successive scans (100 ms debounce).
///
/// Tests drive this coordinator by calling ``handleScannedItem(_:)`` directly
/// without involving real hardware.
@Observable
@MainActor
public final class BarcodeCoordinator: NSObject {

    // MARK: - Published state

    /// `true` while the scanner VC is running.
    public private(set) var isScanning: Bool = false

    /// Set when the scanner cannot start (unsupported, denied, etc.).
    public private(set) var scanError: BarcodeError?

    /// Most recently accepted barcode. Reset to `nil` between scans in
    /// `.continuous` mode once the caller has consumed it.
    public private(set) var lastScanned: Barcode?

    /// Authorization status. Updated on `startIfAuthorized()`.
    public private(set) var authStatus: AVAuthorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .video)

    /// `true` when the current device / OS supports `DataScannerViewController`.
    public let isScannerSupported: Bool

    // MARK: - Configuration

    public let mode: BarcodeScanMode

    // MARK: - Private

    private let onScan: @Sendable (Barcode) -> Void
    private var lastScanTime: Date = .distantPast
    private static let debounceDuration: TimeInterval = 0.1

    // Supported symbologies per §17.2 spec.
    static let recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType> = [
        .barcode(symbologies: [
            .ean13,
            .ean8,
            .upce,
            .code128,
            .code39,
            .qr,
            .pdf417,
            .dataMatrix,
            .aztec,
            .itf14,
        ])
    ]

    // MARK: - Init

    public init(mode: BarcodeScanMode = .single, onScan: @escaping @Sendable (Barcode) -> Void) {
        self.mode = mode
        self.onScan = onScan
        self.isScannerSupported = DataScannerViewController.isSupported
            && DataScannerViewController.isAvailable
        super.init()
    }

    // MARK: - Authorization

    /// Requests camera access if needed.
    /// - Returns: `true` when granted.
    public func requestAuthorization() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authStatus = status
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authStatus = AVCaptureDevice.authorizationStatus(for: .video)
            return granted
        case .denied, .restricted:
            scanError = .notAuthorized
            return false
        @unknown default:
            scanError = .notAuthorized
            return false
        }
    }

    // MARK: - Scanning

    /// Called when the scanner VC becomes active.
    public func markScannerStarted() {
        isScanning = true
        scanError = nil
        AppLog.ui.info("BarcodeCoordinator: scanner started")
    }

    /// Called when the scanner VC stops.
    public func markScannerStopped() {
        isScanning = false
        AppLog.ui.info("BarcodeCoordinator: scanner stopped")
    }

    // MARK: - Item handling (testable entry point)

    /// Processes a scanned item from `DataScannerViewController`.
    /// Also callable directly from tests without a real scanner.
    ///
    /// - Parameter item: A `RecognizedItem` from VisionKit.
    public func handleScannedItem(_ item: DataScannerViewController.RecognizedItem) {
        guard case .barcode(let observation) = item else { return }
        guard let payload = observation.payloadStringValue, !payload.isEmpty else { return }

        // Debounce — ignore rapid duplicate triggers.
        let now = Date()
        guard now.timeIntervalSince(lastScanTime) >= Self.debounceDuration else { return }
        lastScanTime = now

        let symbology = observation.observation.symbology.rawValue
        let barcode = Barcode(value: payload, symbology: symbology)

        lastScanned = barcode
        BrandHaptics.success()
        onScan(barcode)

        AppLog.ui.info("BarcodeCoordinator: scanned \(payload, privacy: .private) (\(symbology, privacy: .public))")
    }

    /// Processes a raw payload string. Used by tests that don't have `RecognizedItem`.
    public func handleRawPayload(_ value: String, symbology: String = "unknown") {
        let now = Date()
        guard now.timeIntervalSince(lastScanTime) >= Self.debounceDuration else { return }
        lastScanTime = now

        let barcode = Barcode(value: value, symbology: symbology)
        lastScanned = barcode
        BrandHaptics.success()
        onScan(barcode)
    }

    /// Resets the last scanned item so the scanner is ready for the next code.
    /// Call after consuming ``lastScanned`` in continuous mode.
    public func resetLastScanned() {
        lastScanned = nil
    }
}

// MARK: - DataScannerViewControllerDelegate

extension BarcodeCoordinator: DataScannerViewControllerDelegate {

    nonisolated public func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [DataScannerViewController.RecognizedItem],
        allItems: [DataScannerViewController.RecognizedItem]
    ) {
        guard let first = addedItems.first else { return }
        Task { @MainActor in
            self.handleScannedItem(first)
        }
    }

    nonisolated public func dataScanner(
        _ dataScanner: DataScannerViewController,
        becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
    ) {
        Task { @MainActor in
            self.scanError = .unavailable
            self.isScanning = false
        }
    }
}

#endif
