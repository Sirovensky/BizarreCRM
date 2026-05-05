import Foundation

// MARK: - KioskMode enum

public enum KioskMode: String, Codable, Sendable, CaseIterable {
    case off
    case posOnly
    case clockInOnly
    case training
}

// MARK: - KioskConfig

public struct KioskConfig: Codable, Sendable {
    public var dimAfterSeconds: Int      // default 120
    public var blackoutAfterSeconds: Int // default 300
    public var nightModeStart: Int       // hour 0..23, default 22
    public var nightModeEnd: Int         // hour 0..23, default 6

    public init(
        dimAfterSeconds: Int = 120,
        blackoutAfterSeconds: Int = 300,
        nightModeStart: Int = 22,
        nightModeEnd: Int = 6
    ) {
        self.dimAfterSeconds = dimAfterSeconds
        self.blackoutAfterSeconds = blackoutAfterSeconds
        self.nightModeStart = nightModeStart
        self.nightModeEnd = nightModeEnd
    }
}
