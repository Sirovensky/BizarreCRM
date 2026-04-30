#if canImport(UIKit)
import SwiftUI
import AVFoundation
import UIKit
import Core
import DesignSystem

/// Full-screen camera capture UI supporting single and multi-shot modes.
///
/// - `single` mode: dismisses immediately after one capture.
/// - `multi` mode: accumulates frames; a capture-count pill appears in the top-right;
///   a "Done" button delivers the batch.
///
/// Permissions-denied state follows the glass-card pattern established in
/// `PosScanSheet` — a frosted card with a "Enable in Settings" CTA.
public struct CameraCaptureView: View {

    // MARK: - Mode

    public enum Mode: Sendable {
        case single
        case multi
    }

    // MARK: - Init

    private let mode: Mode
    private let onCaptured: ([Data]) -> Void
    private let onCancel: () -> Void

    public init(
        mode: Mode,
        onCaptured: @escaping ([Data]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onCaptured = onCaptured
        self.onCancel = onCancel
    }

    // MARK: - State

    @State private var service = CameraService()
    @State private var authStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var torchOn: Bool = false
    @State private var showGrid: Bool = false
    @State private var isFrontCamera: Bool = false
    @State private var capturedFrames: [Data] = []
    @State private var isCapturing: Bool = false
    @State private var captureError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch authStatus {
            case .authorized:
                cameraContent
            case .denied, .restricted:
                permissionDeniedCard
            case .notDetermined:
                ProgressView("Requesting camera…")
                    .tint(.bizarreOrange)
                    .foregroundStyle(.white)
            @unknown default:
                permissionDeniedCard
            }
        }
        .task { await ensureAccess() }
    }

    // MARK: - Camera content

    private var cameraContent: some View {
        ZStack(alignment: .bottom) {
            // Live preview fills the screen.
            CameraCapturePreview(service: service, torchOn: $torchOn)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            // Rule-of-thirds grid overlay.
            if showGrid {
                cameraGrid
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // Error toast
            if let err = captureError {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.bizarreError.opacity(0.85), in: Capsule())
                    .padding(.bottom, 120)
                    .transition(.opacity)
            }

            // Multi-shot count pill (top-right)
            if mode == .multi, !capturedFrames.isEmpty {
                countPill
            }

            bottomBar
        }
    }

    // MARK: - Rule-of-thirds grid

    /// Renders a 3×3 rule-of-thirds grid overlay over the camera preview.
    /// §4.8 — "Camera — AVCaptureSession with flash toggle, flip, grid, shutter haptic."
    private var cameraGrid: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // Two vertical lines at 1/3 and 2/3 width.
                p.move(to: CGPoint(x: w / 3, y: 0))
                p.addLine(to: CGPoint(x: w / 3, y: h))
                p.move(to: CGPoint(x: 2 * w / 3, y: 0))
                p.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                // Two horizontal lines at 1/3 and 2/3 height.
                p.move(to: CGPoint(x: 0, y: h / 3))
                p.addLine(to: CGPoint(x: w, y: h / 3))
                p.move(to: CGPoint(x: 0, y: 2 * h / 3))
                p.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.bizarreOnSurface.opacity(0.4), lineWidth: 0.5)
        }
    }

    // MARK: - Count pill

    private var countPill: some View {
        VStack {
            HStack {
                Spacer()
                Text("\(capturedFrames.count)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.white)
                    .frame(minWidth: 28, minHeight: 28)
                    .background(Color.bizarreOrange, in: Circle())
                    .accessibilityLabel("\(capturedFrames.count) photos captured")
                    .padding(.top, BrandSpacing.xl)
                    .padding(.trailing, BrandSpacing.base)
            }
            Spacer()
        }
    }

    // MARK: - Bottom action bar

    private var bottomBar: some View {
        HStack(spacing: BrandSpacing.xl) {
            // Close / Cancel
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.bizarreOnSurface.opacity(0.2), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close camera")
            .accessibilityIdentifier("camera.close")

            Spacer()

            // Capture button
            Button {
                Task { await capture() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(isCapturing ? Color.bizarreOnSurface.opacity(0.6) : Color.white)
                        .frame(width: 60, height: 60)
                        .scaleEffect(isCapturing && !reduceMotion ? 0.9 : 1.0)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                            value: isCapturing
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isCapturing)
            .accessibilityLabel("Capture photo")
            .accessibilityIdentifier("camera.capture")

            Spacer()

            // Right-side controls: torch + grid + flip (vertical stack so they don't crowd)
            VStack(spacing: BrandSpacing.sm) {
                // Torch toggle (disabled on front camera — no front torch on any supported device)
                Button {
                    torchOn.toggle()
                } label: {
                    Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(torchOn ? Color.bizarreOrange : .white)
                        .frame(width: 44, height: 44)
                        .background(Color.bizarreOnSurface.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isFrontCamera)  // front camera has no torch
                .accessibilityLabel(torchOn ? "Turn torch off" : "Turn torch on")
                .accessibilityIdentifier("camera.torch")

                // Grid overlay toggle
                // §4.8 — "Camera — grid"
                Button {
                    showGrid.toggle()
                } label: {
                    Image(systemName: "grid")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(showGrid ? Color.bizarreOrange : .white)
                        .frame(width: 44, height: 44)
                        .background(Color.bizarreOnSurface.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showGrid ? "Hide grid" : "Show grid")
                .accessibilityIdentifier("camera.grid")

                // Camera flip (front/rear)
                // §4.8 — "Camera — flip"
                Button {
                    Task { await flipCamera() }
                } label: {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.bizarreOnSurface.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFrontCamera ? "Switch to rear camera" : "Switch to front camera")
                .accessibilityIdentifier("camera.flip")
            }
        }
        .padding(.horizontal, BrandSpacing.xl)
        .padding(.bottom, BrandSpacing.xxl)
        .overlay(alignment: .top) {
            // "Done" button in multi mode
            if mode == .multi, !capturedFrames.isEmpty {
                Button {
                    BrandHaptics.success()
                    onCaptured(capturedFrames)
                } label: {
                    Label("Done (\(capturedFrames.count))", systemImage: "checkmark")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnOrange)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.sm)
                        .background(Color.bizarreOrange, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done, \(capturedFrames.count) photos ready")
                .accessibilityIdentifier("camera.done")
                .offset(y: -BrandSpacing.xl)
            }
        }
    }

    // MARK: - Permission denied card

    private var permissionDeniedCard: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Camera access needed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("To capture photos, Bizarre CRM needs permission to use your camera.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.base)
            Button {
                openSettings()
            } label: {
                Label("Enable in Settings", systemImage: "gearshape.fill")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.bizarreOrange, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camera.openSettings")
            .accessibilityLabel("Enable camera access in Settings")

            Button("Cancel") { onCancel() }
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("camera.cancelFromPermission")
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

    // MARK: - Private helpers

    private func ensureAccess() async {
        do {
            let granted = try await service.authorize()
            authStatus = granted ? .authorized : .denied
            if granted {
                try await service.startSession()
            }
        } catch {
            authStatus = .denied
            AppLog.ui.error("CameraCaptureView auth failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flipCamera() async {
        do {
            try await service.switchCamera()
            isFrontCamera = await service.isFrontCamera
            // Turn torch off when switching to front (front has no torch).
            if isFrontCamera { torchOn = false }
        } catch {
            captureError = "Could not switch camera: \(error.localizedDescription)"
            AppLog.ui.error("CameraCaptureView flip failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        captureError = nil
        // §4.8 — "Camera — shutter haptic": use medium impact for the tactile
        // shutter feel, distinct from navigation taps.
        BrandHaptics.tapMedium()

        do {
            let data = try await service.capturePhoto()
            switch mode {
            case .single:
                BrandHaptics.success()
                onCaptured([data])
            case .multi:
                BrandHaptics.tapMedium()
                capturedFrames.append(data)
            }
        } catch {
            captureError = error.localizedDescription
            BrandHaptics.error()
            AppLog.ui.error("CameraCaptureView capture failed: \(error.localizedDescription, privacy: .public)")
            // Auto-clear error after 3 s
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            captureError = nil
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
