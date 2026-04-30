#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - ManagerPinRepromptState

/// §39.5 — Tracks the last manager-PIN approval time for the re-prompt window.
///
/// An elevated session (e.g., manager approved a cash drawer action) should
/// not last indefinitely. After `windowSeconds` of inactivity the approval
/// expires and the next elevated operation must re-enter the manager PIN.
///
/// `windowSeconds` default is 300 (5 minutes), matching the idle-lock timeout
/// used in the biometric re-auth helper (§28).
@MainActor
@Observable
public final class ManagerPinRepromptState {

    // MARK: - Configuration
    public static let defaultWindowSeconds: TimeInterval = 300   // 5 min

    private let windowSeconds: TimeInterval

    // MARK: - State
    private(set) var lastApprovalDate: Date? = nil
    private(set) var approvedManagerId: Int64? = nil

    public init(windowSeconds: TimeInterval = ManagerPinRepromptState.defaultWindowSeconds) {
        self.windowSeconds = windowSeconds
    }

    // MARK: - Public API

    /// Returns `true` when an unexpired manager approval exists.
    public var isApproved: Bool {
        guard let last = lastApprovalDate else { return false }
        return Date().timeIntervalSince(last) < windowSeconds
    }

    /// Remaining seconds of the current approval window (0 if expired/nil).
    public var remainingSeconds: TimeInterval {
        guard let last = lastApprovalDate else { return 0 }
        let elapsed = Date().timeIntervalSince(last)
        return max(0, windowSeconds - elapsed)
    }

    /// Record a fresh manager-PIN approval.
    public func recordApproval(managerId: Int64) {
        lastApprovalDate = Date()
        approvedManagerId = managerId
        AppLog.pos.info("Manager PIN re-prompt: approval recorded managerId=\(managerId), window=\(Int(self.windowSeconds))s")
    }

    /// Explicitly expire the approval (e.g., on register close or role change).
    public func invalidate() {
        lastApprovalDate = nil
        approvedManagerId = nil
        AppLog.pos.info("Manager PIN re-prompt: approval invalidated")
    }
}

// MARK: - EnvironmentKey

private struct ManagerPinRepromptStateKey: EnvironmentKey {
    @MainActor private static let defaultState = ManagerPinRepromptState()

    static var defaultValue: ManagerPinRepromptState {
        MainActor.assumeIsolated { defaultState }
    }
}

public extension EnvironmentValues {
    /// Shared manager-PIN re-prompt state, injected at the POS root.
    var managerPinReprompt: ManagerPinRepromptState {
        get { self[ManagerPinRepromptStateKey.self] }
        set { self[ManagerPinRepromptStateKey.self] = newValue }
    }
}

// MARK: - ManagerPinRepromptModifier

/// §39.5 — View modifier that gates an elevated action behind a manager-PIN
/// re-prompt when the prior approval has expired.
///
/// Usage:
/// ```swift
/// Button("Void sale") { triggerVoid = true }
///   .managerPinReprompt(
///       triggered: $triggerVoid,
///       reason: "Void requires manager approval",
///       state: repromptState
///   ) {
///       performVoid()
///   }
/// ```
///
/// - When `state.isApproved` is true the action runs immediately without
///   showing a PIN sheet.
/// - When expired (or never approved) `ManagerPinSheet` is presented.
///   On successful PIN entry the action runs and `state.recordApproval` is
///   called so subsequent actions within the window skip the prompt.
public struct ManagerPinRepromptModifier: ViewModifier {

    @Binding var triggered: Bool
    let reason: String
    let state: ManagerPinRepromptState
    let action: () -> Void

    @State private var showPin: Bool = false

    public func body(content: Content) -> some View {
        content
            .onChange(of: triggered) { _, newValue in
                guard newValue else { return }
                triggered = false
                if state.isApproved {
                    action()
                } else {
                    showPin = true
                }
            }
            .sheet(isPresented: $showPin) {
                ManagerPinSheet(
                    reason: reason,
                    onApproved: { managerId in
                        state.recordApproval(managerId: managerId)
                        showPin = false
                        action()
                    },
                    onCancelled: {
                        showPin = false
                    }
                )
            }
    }
}

public extension View {
    /// Gates `action` behind a manager-PIN re-prompt when the prior approval
    /// window has expired.
    ///
    /// - Parameters:
    ///   - triggered: Flip to `true` to initiate the guarded action. The
    ///     modifier resets it to `false` immediately so it is safe to re-fire.
    ///   - reason: Human-readable explanation shown in `ManagerPinSheet`.
    ///   - state: Shared `ManagerPinRepromptState` object (inject via env or
    ///     pass explicitly).
    ///   - action: Closure executed when the manager PIN is valid.
    func managerPinReprompt(
        triggered: Binding<Bool>,
        reason: String,
        state: ManagerPinRepromptState,
        action: @escaping () -> Void
    ) -> some View {
        modifier(ManagerPinRepromptModifier(
            triggered: triggered,
            reason: reason,
            state: state,
            action: action
        ))
    }
}

// MARK: - ManagerPinRepromptStatusChip

/// §39.5 — Small chip showing how long the current manager approval remains
/// valid, or an "Expired" label when the window has closed.
///
/// Intended for placement near elevated actions in the Z-report or register
/// management screen so managers have visibility into their session.
public struct ManagerPinRepromptStatusChip: View {

    public let state: ManagerPinRepromptState
    @State private var tick: Date = Date()

    public init(state: ManagerPinRepromptState) {
        self.state = state
    }

    public var body: some View {
        Group {
            if state.isApproved {
                approvedChip
            } else if state.lastApprovalDate != nil {
                expiredChip
            }
            // Show nothing when never approved.
        }
        .onReceive(
            Timer.publish(every: 10, on: .main, in: .common).autoconnect()
        ) { date in tick = date }
    }

    private var approvedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("Manager active · \(Int(state.remainingSeconds / 60))m left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.bizarreSuccess)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, 3)
        .background(Color.bizarreSuccess.opacity(0.12), in: Capsule())
        .accessibilityLabel("Manager PIN approved, \(Int(state.remainingSeconds / 60)) minutes remaining")
        .accessibilityIdentifier("managerReprompt.approvedChip")
    }

    private var expiredChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Manager session expired")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.bizarreWarning)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, 3)
        .background(Color.bizarreWarning.opacity(0.12), in: Capsule())
        .accessibilityLabel("Manager PIN session expired, re-entry required")
        .accessibilityIdentifier("managerReprompt.expiredChip")
    }
}

// MARK: - Preview

#Preview("Manager PIN re-prompt — chips") {
    let state = ManagerPinRepromptState(windowSeconds: 300)
    state.recordApproval(managerId: 42)
    return VStack(spacing: BrandSpacing.lg) {
        ManagerPinRepromptStatusChip(state: state)
        ManagerPinRepromptStatusChip(state: ManagerPinRepromptState())
    }
    .padding()
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
