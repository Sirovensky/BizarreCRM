#if canImport(UIKit) && canImport(VisionKit)
import UIKit
import VisionKit
import AVFoundation
import Combine
import Observation
import Core
import DesignSystem

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

    // MARK: - Combine publisher

    /// Emits each accepted ``Barcode`` on the main thread.
    ///
    /// Usage:
    /// ```swift
    /// coordinator.barcodePublisher
    ///     .sink { barcode in handleBarcode(barcode) }
    ///     .store(in: &cancellables)
    /// ```
    public let barcodePublisher: AnyPublisher<Barcode, Never>
    private let barcodeSubject = PassthroughSubject<Barcode, Never>()

    // MARK: - AsyncStream

    /// Returns a new `AsyncStream<Barcode>` that emits every accepted scan
    /// until the stream is cancelled (e.g. on task cancellation or deallocation).
    ///
    /// Usage:
    /// ```swift
    /// for await barcode in coordinator.barcodeStream() {
    ///     handleBarcode(barcode)
    /// }
    /// ```
    public func barcodeStream() -> AsyncStream<Barcode> {
        AsyncStream { continuation in
            // Keep the Combine subscription alive for the lifetime of the stream.
            // Wrap in a class box so the Sendable onTermination closure can hold it.
            final class SubscriptionBox: @unchecked Sendable {
                var cancellable: AnyCancellable?
            }
            let box = SubscriptionBox()
            box.cancellable = barcodePublisher.sink { barcode in
                continuation.yield(barcode)
            }
            continuation.onTermination = { @Sendable _ in
                box.cancellable?.cancel()
            }
        }
    }

    // MARK: - Private

    private let onScan: @Sendable (Barcode) -> Void
    private var lastScanTime: Date = .distantPast
    private static let debounceDuration: TimeInterval = 0.1

    // Supported symbologies per §17.2 spec (all 12 enabled).
    static let recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType> = [
        .barcode(symbologies: [
            .ean13,
            .ean8,
            .upca,   // UPC-A (12-digit retail; distinct case in DataScannerViewController)
            .upce,
            .code128,
            .code39,
            .code93,
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
        self.barcodePublisher = barcodeSubject.eraseToAnyPublisher()
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
    public func handleScannedItem(_ item: RecognizedItem) {
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
        barcodeSubject.send(barcode)

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
        barcodeSubject.send(barcode)
    }

    /// Resets the last scanned item so the scanner is ready for the next code.
    /// Call after consuming ``lastScanned`` in continuous mode.
    public func resetLastScanned() {
        lastScanned = nil
    }

    // MARK: - Torch (flashlight)

    /// Toggle the device torch (flashlight). No-op when no torch hardware.
    public func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            AppLog.ui.warning("BarcodeCoordinator: failed to set torch — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Zoom

    /// Set the camera zoom factor (clamped to device min/max).
    public func setZoom(_ factor: CGFloat) {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        do {
            try device.lockForConfiguration()
            let clamped = max(device.minAvailableVideoZoomFactor,
                              min(factor, device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            AppLog.ui.warning("BarcodeCoordinator: failed to set zoom — \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - DataScannerViewControllerDelegate

extension BarcodeCoordinator: DataScannerViewControllerDelegate {

    nonisolated public func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        // Extract Sendable payload before crossing actor boundary; RecognizedItem is not Sendable.
        guard let first = addedItems.first,
              case .barcode(let observation) = first,
              let payload = observation.payloadStringValue else { return }
        let symbology = observation.observation.symbology.rawValue
        Task { @MainActor in
            self.handleRawPayload(payload, symbology: symbology)
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
