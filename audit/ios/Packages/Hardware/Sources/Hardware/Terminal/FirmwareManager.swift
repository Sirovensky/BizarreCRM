import Foundation
import Observation
import Core

// MARK: - FirmwareUpdatePolicy

/// When firmware updates are allowed to run.
public enum FirmwareUpdatePolicy: String, Sendable, CaseIterable, Codable {
    /// After-hours default — update when staff confirm the shop is closing.
    case afterHours  = "After hours (recommended)"
    /// Immediately — manager accepts the downtime now.
    case immediately = "Immediately"
    /// Never — tenant opts out of in-app firmware management.
    case manual      = "Manual (I'll update on my own)"
}

// MARK: - FirmwareUpdateResult

public enum FirmwareUpdateResult: Sendable, Equatable {
    case success(newVersion: String)
    case failed(reason: String)
    case cancelled
    case noPreviousVersion  // rollback impossible
}

// MARK: - FirmwareKind

/// The category of firmware being tracked.
public enum FirmwareKind: String, Sendable, CaseIterable {
    case cardTerminal = "Card Terminal"
    case receiptPrinter = "Receipt Printer"
}

// MARK: - FirmwareInfo

/// A snapshot of one device's firmware state.
public struct FirmwareInfo: Sendable, Equatable {
    public let kind: FirmwareKind
    public let deviceName: String
    public let currentVersion: String
    public let latestVersion: String
    /// Approximate number of minutes the update process takes.
    public let estimatedDowntimeMinutes: Int
    /// Whether the vendor SDK exposes a rollback capability.
    public let rollbackAvailable: Bool

    public var isUpToDate: Bool { currentVersion == latestVersion }

    public init(
        kind: FirmwareKind,
        deviceName: String,
        currentVersion: String,
        latestVersion: String,
        estimatedDowntimeMinutes: Int = 2,
        rollbackAvailable: Bool = false
    ) {
        self.kind = kind
        self.deviceName = deviceName
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.estimatedDowntimeMinutes = estimatedDowntimeMinutes
        self.rollbackAvailable = rollbackAvailable
    }
}

// MARK: - FirmwareUpdateLogger protocol

/// Abstraction for persisting update audit entries without importing Networking.
public protocol FirmwareUpdateLogger: Sendable {
    /// Called when a firmware update attempt completes (success or failure).
    func logFirmwareUpdate(
        kind: FirmwareKind,
        deviceName: String,
        fromVersion: String,
        toVersion: String,
        result: FirmwareUpdateResult,
        performedBy: String
    ) async
}

// MARK: - FirmwareProvider protocol

/// Abstraction so the manager can query version + trigger updates without
/// importing vendor SDKs directly (BlockChyp SDK, Star SDK, Epson SDK).
///
/// Each concrete adapter (BlockChypFirmwareProvider, StarPrinterFirmwareProvider,
/// EpsonFirmwareProvider) implements this and is injected at construction time.
public protocol FirmwareProvider: Sendable {
    /// Returns the current + latest firmware info for this device.
    /// Returns `nil` if the device is not reachable or the SDK doesn't expose version info.
    func fetchFirmwareInfo() async throws -> FirmwareInfo?
    /// Triggers the firmware update. Should be called only after user confirmation.
    /// - Returns: The new version string if the update succeeded.
    func applyUpdate() async throws -> String
    /// Rolls back to the previous firmware version if the vendor SDK supports it.
    /// Throws `FirmwareUpdateError.rollbackUnsupported` when unavailable.
    func rollback() async throws -> String
}

// MARK: - FirmwareUpdateError

public enum FirmwareUpdateError: Error, LocalizedError, Sendable {
    case deviceUnreachable
    case updateNotAvailable
    case updateFailed(String)
    case rollbackUnsupported
    case rollbackFailed(String)
    case updateDuringOpenHours

    public var errorDescription: String? {
        switch self {
        case .deviceUnreachable:
            return "The device could not be reached. Check that it is powered on and connected."
        case .updateNotAvailable:
            return "No firmware update is currently available."
        case .updateFailed(let detail):
            return "Firmware update failed: \(detail)"
        case .rollbackUnsupported:
            return "This device does not support firmware rollback."
        case .rollbackFailed(let detail):
            return "Firmware rollback failed: \(detail)"
        case .updateDuringOpenHours:
            return "Firmware updates are not allowed during open hours. Close the register before updating."
        }
    }
}

// MARK: - FirmwareManager

/// Coordinates firmware version checks and update flows for all paired hardware.
///
/// Responsibilities:
///   - Poll each registered `FirmwareProvider` for version info.
///   - Surface an outdated-firmware banner when `latestVersion ≠ currentVersion`.
///   - Gate updates behind manager confirmation (policy = `.afterHours` by default).
///   - Never auto-apply without explicit user consent.
///   - Log every attempt + result via `FirmwareUpdateLogger`.
///
/// Usage:
/// ```swift
/// let manager = FirmwareManager(
///     providers: [blockChypProvider, starPrinterProvider],
///     logger: auditLogger
/// )
/// await manager.refresh()
/// ```
@Observable
@MainActor
public final class FirmwareManager {

    // MARK: - Public state

    /// All known firmware snapshots (terminal + printers). Updated by `refresh()`.
    public private(set) var firmwareInfos: [FirmwareInfo] = []

    /// Convenience: infos that are NOT up to date.
    public var outdatedDevices: [FirmwareInfo] {
        firmwareInfos.filter { !$0.isUpToDate }
    }

    /// True when a refresh or update is in flight.
    public private(set) var isLoading: Bool = false

    /// Non-nil when an error occurs during refresh or update.
    public private(set) var errorMessage: String?

    // MARK: - Configuration

    /// When firmware updates are permitted.
    public var updatePolicy: FirmwareUpdatePolicy = .afterHours

    // MARK: - Private

    private let providers: [any FirmwareProvider]
    private let logger: (any FirmwareUpdateLogger)?

    // MARK: - Init

    public init(
        providers: [any FirmwareProvider],
        logger: (any FirmwareUpdateLogger)? = nil
    ) {
        self.providers = providers
        self.logger = logger
    }

    // MARK: - Refresh

    /// Queries every registered provider and updates `firmwareInfos`.
    public func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var results: [FirmwareInfo] = []
        for provider in providers {
            do {
                if let info = try await provider.fetchFirmwareInfo() {
                    results.append(info)
                }
            } catch {
                AppLog.hardware.warning("FirmwareManager: refresh error — \(error.localizedDescription)")
            }
        }
        firmwareInfos = results
    }

    // MARK: - Update

    /// Applies the firmware update for a specific device after user confirmation.
    ///
    /// - Parameters:
    ///   - info: The `FirmwareInfo` returned by `refresh()`.
    ///   - isOpenHours: Pass `true` when the shop is open (blocks `.afterHours` policy).
    ///   - performedBy: Staff name for the audit log.
    /// - Returns: The `FirmwareUpdateResult`.
    ///
    /// Invariants:
    ///   - Never auto-applies. Caller must prompt the user and pass through.
    ///   - Will throw `FirmwareUpdateError.updateDuringOpenHours` if policy forbids it now.
    @discardableResult
    public func applyUpdate(
        for info: FirmwareInfo,
        isOpenHours: Bool,
        performedBy: String = "Manager"
    ) async -> FirmwareUpdateResult {
        // Policy check — never update during open hours when policy = .afterHours.
        if updatePolicy == .afterHours && isOpenHours {
            errorMessage = FirmwareUpdateError.updateDuringOpenHours.localizedDescription
            AppLog.hardware.warning("FirmwareManager: update blocked — open hours + afterHours policy")
            return .failed(reason: "Update blocked during open hours.")
        }

        // Find the provider for this info.
        guard let provider = providers.first(where: { _ in true }) else {
            errorMessage = "No firmware provider found for \(info.deviceName)."
            return .failed(reason: "Provider not found.")
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        AppLog.hardware.info("FirmwareManager: starting update — \(info.deviceName) \(info.currentVersion) → \(info.latestVersion)")

        do {
            let newVersion = try await provider.applyUpdate()
            AppLog.hardware.info("FirmwareManager: update succeeded — \(info.deviceName) now at \(newVersion)")
            await logger?.logFirmwareUpdate(
                kind: info.kind,
                deviceName: info.deviceName,
                fromVersion: info.currentVersion,
                toVersion: newVersion,
                result: .success(newVersion: newVersion),
                performedBy: performedBy
            )
            await refresh()
            return .success(newVersion: newVersion)
        } catch {
            let reason = error.localizedDescription
            AppLog.hardware.error("FirmwareManager: update failed — \(reason)")
            errorMessage = reason
            await logger?.logFirmwareUpdate(
                kind: info.kind,
                deviceName: info.deviceName,
                fromVersion: info.currentVersion,
                toVersion: info.latestVersion,
                result: .failed(reason: reason),
                performedBy: performedBy
            )
            return .failed(reason: reason)
        }
    }

    // MARK: - Rollback

    /// Rolls back the firmware for a device if the vendor supports it.
    @discardableResult
    public func rollback(
        for info: FirmwareInfo,
        performedBy: String = "Manager"
    ) async -> FirmwareUpdateResult {
        guard info.rollbackAvailable else {
            errorMessage = FirmwareUpdateError.rollbackUnsupported.localizedDescription
            return .noPreviousVersion
        }

        guard let provider = providers.first(where: { _ in true }) else {
            return .failed(reason: "Provider not found.")
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let rolledBackVersion = try await provider.rollback()
            AppLog.hardware.info("FirmwareManager: rollback succeeded — \(info.deviceName) back to \(rolledBackVersion)")
            await logger?.logFirmwareUpdate(
                kind: info.kind,
                deviceName: info.deviceName,
                fromVersion: info.currentVersion,
                toVersion: rolledBackVersion,
                result: .success(newVersion: rolledBackVersion),
                performedBy: performedBy
            )
            await refresh()
            return .success(newVersion: rolledBackVersion)
        } catch {
            let reason = error.localizedDescription
            errorMessage = reason
            return .failed(reason: reason)
        }
    }
}
