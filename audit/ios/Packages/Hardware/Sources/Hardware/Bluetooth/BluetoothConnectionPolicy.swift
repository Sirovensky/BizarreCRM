import Foundation
import Core

// MARK: - BluetoothConnectionPolicy
//
// §17 Bluetooth severity policies + auto-retry backoff:
//  - Scanner offline: silent (badge only, no banner)
//  - Printer offline: surfaces banner (POS needs it)
//  - Terminal offline: blocker (can't charge cards)
//  - Auto-retry on disconnect every 5s up to 30s, then exponential backoff (every 60s)
//  - Manual "Reconnect" button bypasses backoff
//  - Log connection events for troubleshooting

// MARK: - DeviceKind extensions for offline severity + display
// (DeviceKind enum is declared in BluetoothDevice.swift)

extension DeviceKind {

    // MARK: - Severity

    /// Offline severity policy for this device kind.
    /// §17: scanner offline = silent; printer offline = banner; terminal offline = blocker.
    public var offlineSeverity: OfflineSeverity {
        switch self {
        case .scanner:       return .silent
        case .scale:         return .silent
        case .drawer:        return .silent
        case .unknown:       return .silent
        case .receiptPrinter: return .banner
        case .cardReader:    return .blocker
        }
    }

    // MARK: - Display

    public var systemImageName: String {
        switch self {
        case .scanner:       return "barcode.viewfinder"
        case .receiptPrinter: return "printer"
        case .cardReader:    return "creditcard"
        case .scale:         return "scalemass"
        case .drawer:        return "tray.full"
        case .unknown:       return "dot.radiowaves.left.and.right"
        }
    }

    public var displayName: String {
        switch self {
        case .scanner:       return "Scanner"
        case .receiptPrinter: return "Receipt Printer"
        case .cardReader:    return "Card Reader"
        case .scale:         return "Scale"
        case .drawer:        return "Cash Drawer"
        case .unknown:       return "Peripheral"
        }
    }
}

// MARK: - OfflineSeverity

/// How the UI should react when a Bluetooth device goes offline.
public enum OfflineSeverity: Sendable {
    /// Only a small badge; no disruption to the current screen.
    case silent
    /// A dismissable banner appears (e.g. "Printer offline").
    case banner
    /// A blocking alert; the relevant action (e.g. card payment) is disabled.
    case blocker
}

// MARK: - BluetoothRetryPolicy

/// Stateless value type that computes the next retry interval
/// given how many consecutive failed attempts have occurred.
///
/// Policy:
///  - Attempts 1–6 (≤ 30 s window): every 5 s  → stops automatic retries at 30 s
///  - Attempts 7+: every 60 s (exponential saves battery on sustained outage)
///  - Manual reconnect resets the counter.
public struct BluetoothRetryPolicy: Sendable {

    /// Maximum number of short-interval (5 s) retries.
    public let shortRetryCount: Int
    /// Short-interval retry gap.
    public let shortRetryInterval: TimeInterval
    /// Long-interval retry gap after short retries exhausted.
    public let longRetryInterval: TimeInterval

    public init(
        shortRetryCount: Int = 6,        // 6 × 5 s = 30 s
        shortRetryInterval: TimeInterval = 5,
        longRetryInterval: TimeInterval = 60
    ) {
        self.shortRetryCount = shortRetryCount
        self.shortRetryInterval = shortRetryInterval
        self.longRetryInterval = longRetryInterval
    }

    /// Returns the interval to wait before the next retry attempt.
    /// - Parameter attemptNumber: 1-based index of the upcoming attempt.
    public func interval(for attemptNumber: Int) -> TimeInterval {
        attemptNumber <= shortRetryCount ? shortRetryInterval : longRetryInterval
    }

    /// `true` if the retry loop should continue (always — only manual disconnect stops it).
    public var shouldContinue: Bool { true }
}

// MARK: - PeripheralConnectionLog

/// Immutable record of a single Bluetooth connection event.
public struct PeripheralConnectionLog: Identifiable, Sendable {

    public enum Event: Sendable, CustomStringConvertible {
        case connected
        case disconnected(error: String?)
        case reconnecting(attempt: Int)
        case reconnected
        case failed(error: String)

        public var description: String {
            switch self {
            case .connected:                    return "Connected"
            case .disconnected(let e):          return e.map { "Disconnected: \($0)" } ?? "Disconnected"
            case .reconnecting(let n):          return "Reconnecting (attempt \(n))"
            case .reconnected:                  return "Reconnected"
            case .failed(let e):                return "Failed: \(e)"
            }
        }
    }

    public let id: UUID
    public let deviceId: UUID
    public let deviceName: String
    public let kind: DeviceKind?
    public let event: Event
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        deviceId: UUID,
        deviceName: String,
        kind: DeviceKind?,
        event: Event,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.kind = kind
        self.event = event
        self.timestamp = timestamp
    }
}

// MARK: - PeripheralConnectionLogger

/// Ring-buffer log of recent connection events for troubleshooting.
///
/// Thread-safe: actor. Caller awaits to append or query.
public actor PeripheralConnectionLogger {

    private var entries: [PeripheralConnectionLog] = []
    private let maxEntries: Int

    public init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
    }

    /// Append a new log entry; evicts oldest when over limit.
    public func log(
        deviceId: UUID,
        deviceName: String,
        kind: DeviceKind?,
        event: PeripheralConnectionLog.Event
    ) {
        let entry = PeripheralConnectionLog(
            deviceId: deviceId,
            deviceName: deviceName,
            kind: kind,
            event: event
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        AppLog.hardware.info(
            "BT[\(deviceName, privacy: .public)] \(entry.event.description, privacy: .public) at \(entry.timestamp.formatted(.dateTime), privacy: .public)"
        )
    }

    /// All logged entries, newest first.
    public func allEntries() -> [PeripheralConnectionLog] {
        entries.reversed()
    }

    /// Entries for a specific device.
    public func entries(for deviceId: UUID) -> [PeripheralConnectionLog] {
        entries.filter { $0.deviceId == deviceId }.reversed()
    }

    /// Clear all entries (e.g. after a "Clear log" user action).
    public func clear() {
        entries.removeAll()
    }
}

// MARK: - PeripheralOfflineState

/// Published state for one peripheral — drives banner / blocker UI.
@Observable
@MainActor
public final class PeripheralOfflineState {

    public let deviceId: UUID
    public let deviceName: String
    public let kind: DeviceKind?

    /// Current severity of the offline condition.
    public private(set) var severity: OfflineSeverity
    /// True when the device is currently offline.
    public private(set) var isOffline: Bool = false
    /// Current retry attempt number (0 = not retrying).
    public private(set) var retryAttempt: Int = 0
    /// User-visible message.
    public var bannerMessage: String {
        guard isOffline else { return "" }
        let name = deviceName
        switch severity {
        case .silent:
            return "\(name) is offline."
        case .banner:
            return "\(name) is offline. Check the connection or power."
        case .blocker:
            return "\(name) is offline. Card payments are unavailable until reconnected."
        }
    }

    public init(deviceId: UUID, deviceName: String, kind: DeviceKind?) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.kind = kind
        self.severity = kind?.offlineSeverity ?? .silent
    }

    func markOffline(attempt: Int) {
        isOffline = true
        retryAttempt = attempt
    }

    func markOnline() {
        isOffline = false
        retryAttempt = 0
    }
}
