#if canImport(UIKit)
import SwiftUI
import AVFoundation
import UIKit
import Core
import DesignSystem

#if canImport(VisionKit)
import VisionKit
#endif

/// Barcode scan sheet presented from the POS search field. Wraps
/// `DataScannerViewController` (iOS 16+, VisionKit) and delivers the
/// first matched payload back to the caller, with haptic feedback.
///
/// Gracefully degrades on three failure modes:
/// - VisionKit unavailable at compile time → "unsupported device" card
/// - Scanner not supported on this hardware → "unsupported device" card
/// - Camera permission denied → glass error card + "Enable in Settings" CTA
public struct PosScanSheet: View {
    /// Called once with a non-empty scanned payload. The parent sheet
    /// binding should be flipped to `false` after this fires.
    let onScanned: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraAuthorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    public init(onScanned: @escaping (String) -> Void) {
        self.onScanned = onScanned
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("pos.scan.cancel")
                }
            }
        }
        .task { await ensureCameraAccess() }
    }

    @ViewBuilder
    private var content: some View {
        switch cameraAuthorization {
        case .authorized:
            scanner
        case .denied, .restricted:
            permissionDenied
        case .notDetermined:
            ProgressView("Requesting camera…")
                .tint(.bizarreOrange)
                .foregroundStyle(.bizarreOnSurfaceMuted)
        @unknown default:
            permissionDenied
        }
    }

    @ViewBuilder
    private var scanner: some View {
        #if canImport(VisionKit)
        if #available(iOS 16.0, *), DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            BarcodeScannerRepresentable { code in
                BrandHaptics.success()
                onScanned(code)
                dismiss()
            }
            .ignoresSafeArea()
            .accessibilityIdentifier("pos.scan.camera")
        } else {
            unsupportedCard
        }
        #else
        unsupportedCard
        #endif
    }

    private var unsupportedCard: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Scanner unavailable")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("This device doesn't support the live barcode scanner. Tap a result instead.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .padding(BrandSpacing.lg)
    }

    private var permissionDenied: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Camera access needed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("To scan barcodes, Bizarre CRM needs permission to use your camera.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button {
                openSettings()
            } label: {
                Label("Enable in Settings", systemImage: "gearshape.fill")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.bizarreOrange, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pos.scan.openSettings")
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: 420)
        .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.bizarreError.opacity(0.4), lineWidth: 0.5)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
        .padding(BrandSpacing.lg)
    }

    /// Resolves current camera permission — asks if undetermined. Keeping
    /// this inside the sheet avoids mutating AVCaptureDevice state before
    /// the user reaches for the scan button.
    private func ensureCameraAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorization = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuthorization = granted ? .authorized : .denied
        case .denied:
            cameraAuthorization = .denied
        case .restricted:
            cameraAuthorization = .restricted
        @unknown default:
            cameraAuthorization = .denied
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#if canImport(VisionKit)
/// `UIViewControllerRepresentable` wrapper around `DataScannerViewController`.
/// Symbologies cover the common retail set — EAN/UPC families + Code 128 +
/// QR for merchant self-serve stickers.
@available(iOS 16.0, *)
private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onMatch: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMatch: onMatch)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        context.coordinator.controller = vc
        do {
            try vc.startScanning()
        } catch {
            AppLog.hardware.error("DataScanner startScanning failed: \(error.localizedDescription, privacy: .public)")
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    /// Delegate bridge. Stops the scanner after the first match so we
    /// don't fire `onMatch` twice on the dismiss frame.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onMatch: (String) -> Void
        weak var controller: DataScannerViewController?
        private var didFire = false

        init(onMatch: @escaping (String) -> Void) {
            self.onMatch = onMatch
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item: item)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let first = addedItems.first else { return }
            handle(item: first)
        }

        private func handle(item: RecognizedItem) {
            guard !didFire, case let .barcode(b) = item, let payload = b.payloadStringValue, !payload.isEmpty else { return }
            didFire = true
            controller?.stopScanning()
            onMatch(payload)
        }
    }
}
#endif
#endif
