#if canImport(SwiftUI)
import SwiftUI
import AVFoundation
import Core

// MARK: - CameraPermissionReprompt
//
// §17.1 / §17.2 — Camera permission re-prompt UX.
//
// iOS only shows the system camera-permission dialog once. After the user denies
// it, subsequent calls to `AVCaptureDevice.requestAccess(for:)` return `false`
// immediately without showing any dialog. The only way to re-enable camera access
// is for the user to navigate to Settings → Privacy → Camera → <app> and toggle
// the switch on.
//
// This file provides:
//   1. `CameraAuthorizationStatus`    — typed enum wrapping AVAuthorizationStatus
//      with display + accessibility helpers.
//   2. `CameraPermissionMonitor`      — @Observable that tracks the current camera
//      authorization state and refreshes it when the app foregrounds.
//   3. `CameraPermissionRepromptCard` — glass "permission denied" card with a
//      clear call-to-action that opens the iOS Settings deep-link.
//   4. `CameraPermissionGate`         — wrapper that renders child content when
//      camera is authorized and the reprompt card otherwise.
//
// Usage (scanner or camera capture screen):
// ```swift
// CameraPermissionGate {
//     PosScanSheet(...)
// }
// ```

// MARK: - CameraAuthorizationStatus

/// Typed camera authorization state with display helpers.
public enum CameraAuthorizationStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized

    public init(_ avStatus: AVAuthorizationStatus) {
        switch avStatus {
        case .notDetermined:   self = .notDetermined
        case .restricted:      self = .restricted
        case .denied:          self = .denied
        case .authorized:      self = .authorized
        @unknown default:      self = .notDetermined
        }
    }

    public var isAuthorized: Bool { self == .authorized }

    public var requiresSettingsNavigation: Bool {
        self == .denied || self == .restricted
    }

    public var displayTitle: String {
        switch self {
        case .notDetermined:  return "Camera Access Needed"
        case .restricted:     return "Camera Restricted"
        case .denied:         return "Camera Access Denied"
        case .authorized:     return "Camera Authorized"
        }
    }

    public var displayBody: String {
        switch self {
        case .notDetermined:
            return "Grant camera access to scan barcodes and capture photos."
        case .restricted:
            return "Camera access is restricted on this device (e.g. by Screen Time or MDM). Contact your administrator."
        case .denied:
            return "Camera access was denied. To enable barcode scanning and photo capture, allow camera access in Settings."
        case .authorized:
            return "Camera access is enabled."
        }
    }

    public var ctaLabel: String {
        switch self {
        case .notDetermined: return "Allow Camera Access"
        case .denied:        return "Open Settings"
        case .restricted:    return "Contact Administrator"
        case .authorized:    return ""
        }
    }

    public var systemImage: String {
        switch self {
        case .notDetermined: return "camera.circle"
        case .restricted:    return "lock.slash"
        case .denied:        return "camera.slash.fill"
        case .authorized:    return "camera.fill"
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .notDetermined: return "Camera permission not yet requested"
        case .restricted:    return "Camera access restricted by device policy"
        case .denied:        return "Camera access denied — open Settings to enable"
        case .authorized:    return "Camera access granted"
        }
    }
}

// MARK: - CameraPermissionMonitor

/// Tracks AVFoundation camera authorization state and refreshes when the app
/// returns to the foreground (so the card dismisses automatically after the
/// user enables access in Settings).
@Observable
@MainActor
public final class CameraPermissionMonitor {

    // MARK: - State

    public private(set) var status: CameraAuthorizationStatus

    // MARK: - Init

    public init() {
        let avStatus = AVCaptureDevice.authorizationStatus(for: .video)
        status = CameraAuthorizationStatus(avStatus)
    }

    // MARK: - Public API

    /// Request camera access (no-op if already determined). Updates `status`.
    public func requestAccess() async {
        guard status == .notDetermined else {
            // Already denied / restricted — send user to Settings.
            openSettings()
            return
        }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        status = granted ? .authorized : .denied
        AppLog.hardware.info("CameraPermissionMonitor: access request result = \(granted)")
    }

    /// Re-check authorization (call on `scenePhase` change to `.active`).
    public func refreshStatus() {
        let avStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let newStatus = CameraAuthorizationStatus(avStatus)
        guard newStatus != status else { return }
        status = newStatus
        AppLog.hardware.info("CameraPermissionMonitor: status refreshed → \(newStatus.displayTitle, privacy: .public)")
    }

    /// Deep-link to the app's camera permission row in iOS Settings.
    public func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        AppLog.hardware.info("CameraPermissionMonitor: opened iOS Settings for camera re-prompt")
    }
}

// MARK: - CameraPermissionRepromptCard

/// Glass card shown when the camera permission is denied or restricted.
///
/// ```swift
/// if !monitor.status.isAuthorized {
///     CameraPermissionRepromptCard(monitor: monitor)
/// }
/// ```
public struct CameraPermissionRepromptCard: View {

    public let monitor: CameraPermissionMonitor
    @Environment(\.scenePhase) private var scenePhase

    public init(monitor: CameraPermissionMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: monitor.status.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(monitor.status.displayTitle)
                    .font(.title3.weight(.semibold))

                Text(monitor.status.displayBody)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !monitor.status.ctaLabel.isEmpty {
                Button {
                    Task { await monitor.requestAccess() }
                } label: {
                    Text(monitor.status.ctaLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(monitor.status.ctaLabel)
                .accessibilityHint(monitor.status == .denied
                    ? "Opens the iOS Settings app to the camera permission toggle"
                    : "Requests camera access from the system")
                .accessibilityIdentifier("camera.permission.cta")
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(monitor.status.accessibilityDescription)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { monitor.refreshStatus() }
        }
    }

    private var iconColor: Color {
        switch monitor.status {
        case .denied, .restricted: return .red
        case .notDetermined:       return .orange
        case .authorized:          return .green
        }
    }
}

// MARK: - CameraPermissionGate

/// Shows `content` when camera is authorized; shows the reprompt card otherwise.
///
/// Automatically refreshes when the app foregrounds so the gate clears as soon
/// as the user returns from granting access in Settings.
///
/// ```swift
/// CameraPermissionGate {
///     BarcodeScannerView(...)
/// }
/// ```
public struct CameraPermissionGate<Content: View>: View {

    @State private var monitor = CameraPermissionMonitor()
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Group {
            if monitor.status.isAuthorized {
                content()
            } else {
                VStack {
                    Spacer()
                    CameraPermissionRepromptCard(monitor: monitor)
                    Spacer()
                }
                .background(Color(UIColor.systemGroupedBackground))
                .task { await monitor.requestAccess() }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("CameraPermissionRepromptCard — denied") {
    let monitor = CameraPermissionMonitor()
    return CameraPermissionRepromptCard(monitor: monitor)
        .padding()
}
#endif
#endif
