#if canImport(UIKit)
import SwiftUI
import AVFoundation
import Core
import DesignSystem

// MARK: - CameraFullScreenLayout

/// iPad-optimised full-screen capture shell.
///
/// Portrait:  preview fills centre column; side panel anchors to trailing edge.
/// Landscape: preview fills left two-thirds; side panel occupies right third.
///
/// Pluggable — wraps ``CameraCapturePreview`` and ``CameraService`` without
/// touching existing `CameraCaptureView`. Callers supply `mode` and callbacks;
/// this view owns the iPad layout shell and Liquid Glass chrome.
///
/// **Not** shown on iPhone — guard with `Platform.isIPad` at the call site or
/// use the `.cameraFullScreenCover(...)` modifier below.
public struct CameraFullScreenLayout: View {

    // MARK: - Init

    public enum Mode: Sendable { case single, multi }

    private let mode: Mode
    private let onCaptured: ([Data]) -> Void
    private let onCancel: () -> Void

    public init(
        mode: Mode = .single,
        onCaptured: @escaping ([Data]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onCaptured = onCaptured
        self.onCancel = onCancel
    }

    // MARK: - State

    @State private var service = CameraService()
    @State private var authStatus: AVAuthorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .video)
    @State private var torchOn = false
    @State private var capturedFrames: [Data] = []
    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var scanHistory: [ScannedBarcodeEntry] = []
    @State private var showHistory = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Landscape on iPad when horizontal is regular AND vertical is compact.
    private var isLandscape: Bool { vSizeClass == .compact }

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch authStatus {
            case .authorized:
                layoutContent
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

    // MARK: - Main layout

    @ViewBuilder
    private var layoutContent: some View {
        if isLandscape {
            HStack(spacing: 0) {
                previewArea
                    .frame(maxWidth: .infinity)
                sidePanel
                    .frame(width: SidePanelLayout.landscapeWidth)
            }
            .ignoresSafeArea()
        } else {
            ZStack(alignment: .trailing) {
                previewArea
                    .ignoresSafeArea()
                if showHistory {
                    ScanHistoryInspector(
                        entries: scanHistory,
                        onClose: { withAnimation { showHistory = false } }
                    )
                    .frame(width: SidePanelLayout.portraitPanelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay(alignment: .trailing) {
                if !showHistory {
                    sidePanelCollapsedHandle
                }
            }
        }
    }

    // MARK: - Preview area (shared between orientations)

    private var previewArea: some View {
        ZStack(alignment: .bottom) {
            CameraCapturePreview(service: service, torchOn: $torchOn)
                .accessibilityHidden(true)

            if let err = captureError {
                errorToast(err)
            }

            if mode == .multi, !capturedFrames.isEmpty {
                countPill
            }

            bottomBar
        }
    }

    // MARK: - Side panel (landscape — always visible)

    private var sidePanel: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            sideToolButtons

            Spacer()

            if mode == .multi, !capturedFrames.isEmpty {
                doneButton
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xxl)
        .brandGlass(.regular, in: Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera tools panel")
    }

    // MARK: - Portrait collapsed handle

    private var sidePanelCollapsedHandle: some View {
        Button {
            withAnimation(.spring(response: DesignTokens.Motion.snappy, dampingFraction: 0.8)) {
                showHistory = true
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                            interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show scan history")
        .accessibilityIdentifier("camera.ipad.historyHandle")
        .padding(.trailing, DesignTokens.Spacing.lg)
    }

    // MARK: - Tool buttons (reused in side panel and bottom bar)

    @ViewBuilder
    private var sideToolButtons: some View {
        BrandGlassContainer {
            VStack(spacing: DesignTokens.Spacing.md) {
                // Close
                Button { onCancel() } label: {
                    toolIcon("xmark", label: "Close camera",
                             id: "camera.ipad.close")
                }
                .buttonStyle(.brandGlass)

                // Torch
                Button { torchOn.toggle() } label: {
                    toolIcon(
                        torchOn ? "bolt.fill" : "bolt.slash.fill",
                        tint: torchOn ? .bizarreOrange : nil,
                        label: torchOn ? "Turn torch off" : "Turn torch on",
                        id: "camera.ipad.torch"
                    )
                }
                .buttonStyle(.brandGlass)

                // History toggle (landscape)
                Button {
                    withAnimation { showHistory.toggle() }
                } label: {
                    toolIcon("clock.arrow.circlepath",
                             tint: showHistory ? .bizarreOrange : nil,
                             label: "Scan history",
                             id: "camera.ipad.history")
                }
                .buttonStyle(.brandGlass)
            }
        }
    }

    // MARK: - Bottom bar (capture button always centred)

    private var bottomBar: some View {
        HStack {
            Spacer()
            captureButton
            Spacer()
        }
        .padding(.bottom, DesignTokens.Spacing.huge)
        .overlay(alignment: .top) {
            if mode == .multi, !capturedFrames.isEmpty {
                doneButton
                    .offset(y: -DesignTokens.Spacing.xl)
            }
        }
    }

    // MARK: - Capture button

    private var captureButton: some View {
        Button {
            Task { await capture() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(isCapturing ? Color.bizarreOnSurface.opacity(0.6) : Color.white)
                    .frame(width: 68, height: 68)
                    .scaleEffect(isCapturing && !reduceMotion ? 0.88 : 1.0)
                    .animation(
                        reduceMotion ? nil
                            : .spring(response: 0.25, dampingFraction: 0.7),
                        value: isCapturing
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
        .accessibilityLabel("Capture photo")
        .accessibilityIdentifier("camera.ipad.capture")
    }

    // MARK: - Done button (multi mode)

    private var doneButton: some View {
        Button {
            BrandHaptics.success()
            onCaptured(capturedFrames)
        } label: {
            Label("Done (\(capturedFrames.count))", systemImage: "checkmark")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnOrange)
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(Color.bizarreOrange, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done, \(capturedFrames.count) photos ready")
        .accessibilityIdentifier("camera.ipad.done")
    }

    // MARK: - Count pill

    private var countPill: some View {
        VStack {
            HStack {
                Spacer()
                Text("\(capturedFrames.count)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.white)
                    .frame(minWidth: 32, minHeight: 32)
                    .background(Color.bizarreOrange, in: Circle())
                    .accessibilityLabel("\(capturedFrames.count) photos captured")
                    .padding(.top, DesignTokens.Spacing.xxl)
                    .padding(.trailing, DesignTokens.Spacing.lg)
            }
            Spacer()
        }
    }

    // MARK: - Error toast

    private func errorToast(_ message: String) -> some View {
        Text(message)
            .font(.brandLabelSmall())
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(Color.bizarreError.opacity(0.85), in: Capsule())
            .padding(.bottom, 140)
            .transition(.opacity)
    }

    // MARK: - Permission denied card

    private var permissionDeniedCard: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "camera.fill")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Camera access needed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("To capture photos, Bizarre CRM needs permission to use your camera.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.lg)
            Button { openSettings() } label: {
                Label("Enable in Settings", systemImage: "gearshape.fill")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(Color.bizarreOrange, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camera.ipad.openSettings")
            Button("Cancel") { onCancel() }
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("camera.ipad.cancelFromPermission")
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: 480)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .padding(DesignTokens.Spacing.xxl)
    }

    // MARK: - Tool icon helper

    private func toolIcon(
        _ systemName: String,
        tint: Color? = nil,
        label: String,
        id: String
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(tint ?? .white)
            .frame(width: 52, height: 52)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
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
            AppLog.ui.error("CameraFullScreenLayout auth failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        captureError = nil
        BrandHaptics.tap()

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
            AppLog.ui.error("CameraFullScreenLayout capture failed: \(error.localizedDescription, privacy: .public)")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            captureError = nil
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - SidePanelLayout tokens

private enum SidePanelLayout {
    static let landscapeWidth: CGFloat = 96
    static let portraitPanelWidth: CGFloat = 320
}

#endif
