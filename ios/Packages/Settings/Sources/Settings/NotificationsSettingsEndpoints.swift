import Foundation
import Networking

// MARK: - Notifications settings endpoints (§19.3)
// Called from NotificationsExtendedPage ViewModel via these typed wrappers.

public struct NotifSettingsWire: Encodable, Sendable {
    public let quietHoursEnabled: Bool
    public let quietHoursStart: String
    public let quietHoursEnd: String
    public let criticalOverride: Bool
}

private struct NotifSettingsStatusWire: Decodable { let success: Bool }
private struct TestPushStatusWire: Decodable { let success: Bool }
private struct EmptyBody: Encodable {}

public extension APIClient {
    func putNotifSettings(_ body: NotifSettingsWire) async throws {
        _ = try await put(
            "/api/v1/settings/notifications",
            body: body,
            as: NotifSettingsStatusWire.self
        )
    }

    func postTestPush() async throws {
        _ = try await post(
            "/api/v1/notifications/test",
            body: EmptyBody(),
            as: TestPushStatusWire.self
        )
    }
}
