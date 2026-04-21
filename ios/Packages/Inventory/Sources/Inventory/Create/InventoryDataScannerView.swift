#if canImport(UIKit)
import SwiftUI
import VisionKit
import DesignSystem

/// Lightweight `UIViewControllerRepresentable` wrapper around
/// `DataScannerViewController` restricted to barcode recognition.
/// Delivers the first decoded symbol string via `onScan` and does not loop.
///
/// This lives inside the Inventory package so we avoid a hard dependency on
/// the Camera package while still reusing VisionKit directly — the Camera
/// package's `CameraService` is photo-capture oriented; barcode scanning in
/// inventory forms needs a simpler integration.
struct InventoryDataScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isAvailable,
              DataScannerViewController.isSupported else {
            return UnavailableScanViewController()
        }
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate, Sendable {
        let onScan: (String) -> Void
        private var didDeliver = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let item = addedItems.first, case .barcode(let barcode) = item else { return }
            guard let value = barcode.payloadStringValue, !value.isEmpty else { return }
            guard !didDeliver else { return }
            didDeliver = true
            dataScanner.stopScanning()
            BrandHaptics.tap()
            onScan(value)
        }
    }
}

/// Fallback controller shown when `DataScannerViewController` is not available
/// (simulator, older iOS, or missing entitlement).
private final class UnavailableScanViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        let label = UILabel()
        label.text = "Barcode scanning not available on this device."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }
}
#endif
