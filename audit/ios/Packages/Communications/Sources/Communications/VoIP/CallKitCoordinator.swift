import Foundation
import CallKit
import AVFoundation
import Core

// MARK: - §12.10 CallKit CXProvider Coordinator

/// Manages `CXProvider` for outbound calls initiated by the Calls tab.
///
/// Ownership note (§12.10):
/// - This coordinator is instantiated by `Communications` package only.
/// - `CXProvider` + `CXCallController` wiring lives here.
/// - PushKit incoming-call handling (`PKPushRegistry`) lives in the App target because
///   it must be wired to `UIApplicationDelegate` — the `voip` UIBackgroundMode and
///   PushKit entitlement were added by Agent 10 b6. The coordinator here handles
///   the CallKit side once the app is woken.
///
/// Sovereignty: call routing goes through the tenant's own server (`POST /voice/call`).
/// No third-party VoIP SDK is imported here (CallKit is an Apple framework, not third-party).
@MainActor
public final class CallKitCoordinator: NSObject, CXProviderDelegate, Sendable {

    // MARK: - Singleton-style shared instance (one provider per app)

    public static let shared = CallKitCoordinator()

    // MARK: - Private state

    private let provider: CXProvider
    private let controller = CXCallController()
    private var activeCalls: [UUID: CallKitCallState] = [:]

    // MARK: - Init

    override private init() {
        let config = CXProviderConfiguration(localizedName: "BizarreCRM")
        config.supportsVideo = false
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.phoneNumber]
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: - Outbound call (§12.10 "Initiate call")

    /// Report an outbound call to CallKit after the server has assigned a `callId`.
    /// Returns the `UUID` for subsequent hangup.
    @discardableResult
    public func reportOutboundCall(
        to phoneNumber: String,
        displayName: String?,
        serverCallId: Int64
    ) -> UUID {
        let uuid = UUID()
        let handle = CXHandle(type: .phoneNumber, value: phoneNumber)
        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.localizedCallerName = displayName ?? phoneNumber
        update.hasVideo = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false

        activeCalls[uuid] = CallKitCallState(serverCallId: serverCallId, uuid: uuid, phoneNumber: phoneNumber)

        // Tell CallKit we are starting an outbound call.
        let action = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(action: action)
        Task {
            try? await controller.request(transaction)
        }

        return uuid
    }

    // MARK: - Hangup

    /// End a call identified by its UUID (from `reportOutboundCall`).
    public func hangup(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        Task {
            try? await controller.request(transaction)
        }
    }

    // MARK: - Incoming push (§12.10 incoming call push — PushKit triggers this)

    /// Called by the App target's PushKit delegate when a VoIP push arrives.
    /// Presents the native incoming-call UI via `CXProvider.reportNewIncomingCall`.
    public func reportIncomingCall(
        uuid: UUID,
        phoneNumber: String,
        callerName: String?,
        serverCallId: Int64
    ) {
        let handle = CXHandle(type: .phoneNumber, value: phoneNumber)
        let update = CXCallUpdate()
        update.remoteHandle = handle
        update.localizedCallerName = callerName ?? phoneNumber
        update.hasVideo = false

        activeCalls[uuid] = CallKitCallState(serverCallId: serverCallId, uuid: uuid, phoneNumber: phoneNumber)

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                // Non-fatal: the call may have already been cancelled server-side.
                print("[CallKitCoordinator] reportNewIncomingCall error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - CXProviderDelegate

    public nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in
            activeCalls.removeAll()
        }
    }

    public nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // Outbound call started — configure audio session.
        configureAudioSession()
        action.fulfill()
    }

    public nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        configureAudioSession()
        action.fulfill()
    }

    public nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        let callUUID = action.callUUID
        Task { @MainActor in
            activeCalls.removeValue(forKey: callUUID)
        }
    }

    public nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Audio session is now active — nothing extra needed for click-to-call mode.
    }

    public nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        // Restore app audio session if needed.
    }

    // MARK: - Private helpers

    nonisolated private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try? session.setActive(true)
    }
}

// MARK: - Call State

private struct CallKitCallState: Sendable {
    let serverCallId: Int64
    let uuid: UUID
    let phoneNumber: String
}
