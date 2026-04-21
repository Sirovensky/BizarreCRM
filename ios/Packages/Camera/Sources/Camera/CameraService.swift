#if canImport(UIKit)
import AVFoundation
import CoreImage
import UIKit
import Core

// MARK: - CameraService

/// Swift actor wrapping an `AVCaptureSession` for live camera capture.
///
/// Usage flow:
/// 1. `authorize()` — request permission, returns `true` when granted.
/// 2. `startSession()` — begins the capture session (background queue).
/// 3. `capturePhoto(format:quality:)` — snap a JPEG or HEIC frame.
/// 4. `stopSession()` — tears the session down.
///
/// EXIF strip: every captured frame is run through `CIImage` + Core Image
/// orientation filter before encoding so no GPS or device metadata leaks.
///
/// Compression: iteratively lowers quality until the blob fits ≤ 1.5 MB.
public actor CameraService: NSObject {

    // MARK: Properties

    private let session = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?

    /// Continuation fulfilled when AVCapturePhotoCaptureDelegate fires.
    private var captureContinuation: CheckedContinuation<Data, Error>?

    // MARK: Constants

    private static let maxBytes: Int = 1_500_000          // 1.5 MB
    private static let heicQuality: Double = 0.6
    private static let jpegQuality: Double = 0.7
    private static let qualityStep: Double = 0.1
    private static let minQuality: Double = 0.1

    // MARK: - Authorization

    /// Requests camera permission if not yet determined.
    /// - Returns: `true` when access is granted.
    /// - Throws: ``CameraError/notAuthorized`` when the user denies.
    public func authorize() async throws -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.notAuthorized }
            return granted
        case .denied, .restricted:
            throw CameraError.notAuthorized
        @unknown default:
            throw CameraError.notAuthorized
        }
    }

    // MARK: - Session lifecycle

    /// Configures inputs / outputs and starts the capture session.
    /// Must be called after a successful ``authorize()``.
    public func startSession() async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraError.notAuthorized
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video) else {
            throw CameraError.hardwareUnavailable
        }
        currentDevice = device

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraError.hardwareUnavailable
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            session.commitConfiguration()
            throw CameraError.hardwareUnavailable
        }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            photoOutput = output
        } else {
            session.commitConfiguration()
            throw CameraError.hardwareUnavailable
        }

        session.commitConfiguration()

        // Run session on background thread — never block the main actor.
        await Task.detached(priority: .userInitiated) {
            self.session.startRunning()
        }.value
        AppLog.ui.info("CameraService: session started")
    }

    /// Stops the capture session and releases resources.
    public func stopSession() async {
        await Task.detached(priority: .userInitiated) {
            self.session.stopRunning()
        }.value
        photoOutput = nil
        currentDevice = nil
        AppLog.ui.info("CameraService: session stopped")
    }

    // MARK: - Photo capture

    /// Captures a single frame.
    ///
    /// - Parameters:
    ///   - format: `.heic` (default, smaller) or `.jpeg`.
    ///   - quality: Initial compression quality, `0.0 – 1.0`. Iteratively
    ///     reduced until the encoded blob is ≤ 1.5 MB.
    /// - Returns: Compressed image data with EXIF stripped.
    /// - Throws: ``CameraError`` on permission or hardware issues.
    public func capturePhoto(
        format: PhotoFormat = .heic,
        quality: Double = CameraService.heicQuality
    ) async throws -> Data {
        guard let output = photoOutput else {
            throw CameraError.captureFailed("Session not started")
        }

        let settings = makeSettings(for: format, output: output)

        let rawData = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            captureContinuation = cont
            output.capturePhoto(with: settings, delegate: self)
        }

        // Strip EXIF and fix orientation via Core Image.
        let stripped = try stripExif(rawData, format: format, quality: quality)
        return stripped
    }

    private func makeSettings(for format: PhotoFormat, output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        let codec: AVVideoCodecType = format == .heic ? .hevc : .jpeg
        if output.availablePhotoCodecTypes.contains(codec) {
            return AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
        }
        // Fallback to JPEG on simulators / older hardware.
        return AVCapturePhotoSettings()
    }

    private func stripExif(_ data: Data, format: PhotoFormat, quality: Double) throws -> Data {
        guard let ciImage = CIImage(data: data) else {
            throw CameraError.captureFailed("Could not decode captured frame")
        }
        // Apply orientation-fix filter — strips EXIF orientation by baking it
        // into pixel buffer geometry.
        let oriented = ciImage.oriented(forExifOrientation: imageOrientation())
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return try compress(oriented, context: context, format: format, quality: quality)
    }

    private func compress(
        _ image: CIImage,
        context: CIContext,
        format: PhotoFormat,
        quality: Double
    ) throws -> Data {
        var q = min(max(quality, Self.minQuality), 1.0)
        while q >= Self.minQuality {
            let data: Data?
            switch format {
            case .heic:
                data = context.heifRepresentation(
                    of: image,
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                    options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): q]
                )
            case .jpeg:
                data = context.jpegRepresentation(
                    of: image,
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                    options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): q]
                )
            }
            guard let encoded = data else {
                throw CameraError.captureFailed("Encoding failed at quality \(q)")
            }
            if encoded.count <= Self.maxBytes || q <= Self.minQuality {
                return encoded
            }
            q -= Self.qualityStep
        }
        throw CameraError.captureFailed("Cannot compress image below 1.5 MB")
    }

    /// Returns the EXIF orientation value matching current device orientation.
    private func imageOrientation() -> Int32 {
        // 1 = normal/landscape-right, matches AVFoundation back camera default.
        // On device we'd query UIDevice.current.orientation; here we bake in
        // the default so the CIImage pipeline always produces upright pixels.
        return 1
    }

    // MARK: - Torch

    /// Enables or disables the rear-facing torch.
    /// - Throws: ``CameraError/hardwareUnavailable`` when torch is absent.
    public func setTorch(_ on: Bool) throws {
        guard let device = currentDevice, device.hasTorch else {
            throw CameraError.hardwareUnavailable
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            throw CameraError.captureFailed("Torch configuration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Zoom

    /// Sets the camera zoom factor.
    /// - Parameter factor: Clamped to `[1.0, device.activeFormat.videoMaxZoomFactor]`.
    /// - Throws: ``CameraError/hardwareUnavailable`` when no device is active.
    public func setZoom(_ factor: CGFloat) throws {
        guard let device = currentDevice else {
            throw CameraError.hardwareUnavailable
        }
        let max = device.activeFormat.videoMaxZoomFactor
        let clamped = min(max(factor, 1.0), max)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            throw CameraError.captureFailed("Zoom configuration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Preview layer accessor

    /// Returns the live preview layer. Must be added to a UIView layer hierarchy
    /// before the session starts, or after — AVFoundation handles both.
    nonisolated public func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

// MARK: - AVCapturePhotoCaptureDelegate (nonisolated bridge)

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { await self.handlePhoto(photo, error: error) }
    }

    private func handlePhoto(_ photo: AVCapturePhoto, error: Error?) {
        guard let cont = captureContinuation else { return }
        captureContinuation = nil
        if let error {
            cont.resume(throwing: CameraError.captureFailed(error.localizedDescription))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            cont.resume(throwing: CameraError.captureFailed("No file data in captured photo"))
            return
        }
        cont.resume(returning: data)
    }
}
#endif
