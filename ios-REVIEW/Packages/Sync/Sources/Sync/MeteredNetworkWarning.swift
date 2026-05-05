import SwiftUI
import Networking

// §20.6 — Metered-network warning
//
// When the device is on an expensive (cellular or hotspot) connection AND
// the user tries to upload a photo/binary, we pause the upload and show a
// glass banner: "Using cellular data — photo uploads paused until Wi-Fi."
//
// User can override per-session via a "Upload anyway" action.
// The preference is stored in `MeteredUploadPolicy` (in-memory; resets each launch).

// MARK: - MeteredUploadPolicy

/// In-memory per-session policy for binary uploads on expensive networks.
///
/// Default: pause uploads on expensive (cellular / Personal Hotspot) connections.
/// User can override for the current session via `allowOnMetered()`.
@MainActor
@Observable
public final class MeteredUploadPolicy {

    public static let shared = MeteredUploadPolicy()

    /// `true` when the user has explicitly allowed uploads on metered connections
    /// for the current session. Resets to `false` on app restart.
    public private(set) var userAllowedOnMetered: Bool = false

    private init() {}

    /// User taps "Upload anyway" — allow uploads on metered for this session.
    public func allowOnMetered() {
        userAllowedOnMetered = true
    }

    /// Reset the override (e.g., on foreground or new session).
    public func reset() {
        userAllowedOnMetered = false
    }

    /// Returns `true` if a photo/binary upload should be paused right now.
    ///
    /// Paused when:
    ///   - The connection is expensive (cellular / Personal Hotspot).
    ///   - The user has NOT overridden for this session.
    public func shouldPauseUpload(reachability: Reachability) -> Bool {
        reachability.isExpensive && !userAllowedOnMetered
    }
}

// MARK: - MeteredNetworkWarningModifier

/// §20.6 — Shows a glass banner when uploads are paused due to metered network.
///
/// Attach on screens that trigger photo or binary uploads (ticket detail,
/// expense receipt, customer avatar).
///
/// ```swift
/// TicketDetailView()
///     .meteredNetworkWarning(isUploadPending: viewModel.hasPhotoUploadPending)
/// ```
public struct MeteredNetworkWarningModifier: ViewModifier {
    @Environment(Reachability.self) private var reachability: Reachability?
    @State private var policy = MeteredUploadPolicy.shared

    /// `true` when the caller has a pending photo/binary upload in the queue.
    public let isUploadPending: Bool

    public init(isUploadPending: Bool) {
        self.isUploadPending = isUploadPending
    }

    private var shouldWarn: Bool {
        guard isUploadPending, let reach = reachability else { return false }
        return policy.shouldPauseUpload(reachability: reach)
    }

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if shouldWarn {
                    meteredBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.20), value: shouldWarn)
                }
            }
    }

    private var meteredBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Using cellular data")
                    .font(.caption.weight(.semibold))
                Text("Photo uploads paused until Wi-Fi")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Upload anyway") {
                MeteredUploadPolicy.shared.allowOnMetered()
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Using cellular data. Photo uploads paused until Wi-Fi. Tap 'Upload anyway' to override.")
    }
}

// MARK: - View extension

public extension View {
    /// §20.6 — Displays a cellular-data warning banner when photo uploads
    /// are paused because the device is on an expensive metered connection.
    ///
    /// - Parameter isUploadPending: Pass `true` when there is at least one
    ///   binary/photo upload queued for this screen.
    func meteredNetworkWarning(isUploadPending: Bool) -> some View {
        modifier(MeteredNetworkWarningModifier(isUploadPending: isUploadPending))
    }
}
