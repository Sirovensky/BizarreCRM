import Foundation
import Core

// MARK: - ChannelTestAction
//
// §70 Matrix — Send-test-to-self action.
//
// The server currently has no `POST /api/v1/notification-preferences/test`
// route.  This file wires the action so it is ready to enable when the
// backend ships the endpoint.  Until then every call returns
// `.unavailable` so the UI can hide or grey-out the test button.

// MARK: - ChannelTestResult

public enum ChannelTestResult: Sendable, Equatable {
    /// Test notification was dispatched successfully.
    case sent
    /// The server does not yet expose a test-send route for this channel.
    case unavailable
    /// The server returned an error.
    case failed(String)
}

// MARK: - ChannelTestAction

/// Sends a test notification to the current user via a specific channel.
///
/// Usage:
/// ```swift
/// let result = await ChannelTestAction.send(channel: .push, via: apiClient)
/// ```
public enum ChannelTestAction {

    // MARK: - Server route guard

    /// `true` when the server exposes the test-send route.
    /// Flip to `true` when `POST /api/v1/notification-preferences/test` ships.
    public static let isRouteAvailable: Bool = false

    // MARK: - Public API

    /// Attempt to send a test notification for the given channel.
    ///
    /// - Parameters:
    ///   - channel: The delivery channel to test.
    ///   - event:   Optional event type for the test payload (defaults to a generic ping).
    ///   - api:     The live APIClient. Only used when `isRouteAvailable` is `true`.
    /// - Returns: A `ChannelTestResult` indicating outcome.
    public static func send(
        channel: MatrixChannel,
        event: NotificationEvent? = nil,
        via api: (any Sendable)? = nil
    ) async -> ChannelTestResult {
        guard isRouteAvailable else {
            AppLog.ui.debug("ChannelTestAction: route unavailable — skipping test for \(channel.rawValue, privacy: .public)")
            return .unavailable
        }

        // --- Placeholder for when the route ships ---
        // Expected call:
        //   POST /api/v1/notification-preferences/test
        //   Body: { "channel": "<push|email|sms>", "event_type": "<optional>" }
        //   Envelope: { success, data: { dispatched: Bool }, message }
        //
        // Uncomment + adapt when the server endpoint is added:
        //
        // guard let client = api as? any APIClient else { return .unavailable }
        // do {
        //     struct TestBody: Encodable, Sendable {
        //         let channel: String
        //         let eventType: String?
        //         enum CodingKeys: String, CodingKey {
        //             case channel
        //             case eventType = "event_type"
        //         }
        //     }
        //     struct TestResponse: Decodable, Sendable { let dispatched: Bool }
        //     let body = TestBody(channel: channel.rawValue, eventType: event?.rawValue)
        //     let resp = try await client.post(
        //         "/api/v1/notification-preferences/test",
        //         body: body,
        //         as: TestResponse.self
        //     )
        //     return resp.dispatched ? .sent : .failed("Server did not dispatch")
        // } catch {
        //     return .failed(error.localizedDescription)
        // }

        return .unavailable
    }
}
