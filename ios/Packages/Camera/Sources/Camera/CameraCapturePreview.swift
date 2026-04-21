#if canImport(UIKit)
import SwiftUI
import AVFoundation
import UIKit

/// SwiftUI `UIViewRepresentable` that hosts an `AVCaptureVideoPreviewLayer`
/// and bridges pinch-to-zoom gestures through to `CameraService.setZoom(_:)`.
///
/// The preview layer is inserted into the backing `UIView`'s layer hierarchy;
/// its frame tracks the view bounds via `layoutSubviews`.
public struct CameraCapturePreview: UIViewRepresentable {

    private let service: CameraService
    @Binding private var torchOn: Bool

    public init(service: CameraService, torchOn: Binding<Bool>) {
        self.service = service
        self._torchOn = torchOn
    }

    // MARK: UIViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator(service: service)
    }

    public func makeUIView(context: Context) -> PreviewContainerView {
        let container = PreviewContainerView()
        let previewLayer = service.makePreviewLayer()
        container.setPreviewLayer(previewLayer)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        container.addGestureRecognizer(pinch)
        return container
    }

    public func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        // Sync torch state whenever the binding changes.
        context.coordinator.updateTorch(torchOn)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject {
        private let service: CameraService
        /// Zoom factor accumulator — persists between pinch gestures.
        private var lastZoom: CGFloat = 1.0

        init(service: CameraService) {
            self.service = service
        }

        func updateTorch(_ on: Bool) {
            Task {
                try? await service.setTorch(on)
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .changed:
                let factor = lastZoom * gesture.scale
                Task {
                    try? await service.setZoom(factor)
                }
            case .ended:
                lastZoom *= gesture.scale
            default:
                break
            }
        }
    }
}

// MARK: - PreviewContainerView

/// A `UIView` subclass whose layer hosts `AVCaptureVideoPreviewLayer`.
/// Overrides `layoutSubviews` to keep the preview layer flush with bounds.
public final class PreviewContainerView: UIView {

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        self.layer.insertSublayer(layer, at: 0)
        layer.frame = bounds
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
#endif
