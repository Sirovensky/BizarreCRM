import Foundation
import Core
#if canImport(UIKit)
import UIKit
#endif

// MARK: - DiagnosticsBundle

/// JSON-serializable diagnostic bundle attached to support emails and bug reports.
public struct DiagnosticsBundle: Codable, Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let iosVersion: String
    public let deviceModel: String
    public let tenantSlug: String?
    /// Last 20 redacted breadcrumbs (oldest first).
    public let recentBreadcrumbs: [BreadcrumbEntry]
    /// Non-sensitive summary of recent network activity.
    public let networkSummary: String

    public struct BreadcrumbEntry: Codable, Sendable {
        public let timestamp: String
        public let level: String
        public let category: String
        public let message: String

        public init(timestamp: String, level: String, category: String, message: String) {
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
        }
    }

    public init(
        appVersion: String,
        buildNumber: String,
        iosVersion: String,
        deviceModel: String,
        tenantSlug: String?,
        recentBreadcrumbs: [BreadcrumbEntry],
        networkSummary: String
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.iosVersion = iosVersion
        self.deviceModel = deviceModel
        self.tenantSlug = tenantSlug
        self.recentBreadcrumbs = recentBreadcrumbs
        self.networkSummary = networkSummary
    }
}

// MARK: - DiagnosticsBundleBuilder

/// Actor that assembles a `DiagnosticsBundle` for support emails and bug reports.
/// All breadcrumb messages pass through `LogRedactor` — no PII leaks.
public actor DiagnosticsBundleBuilder {

    // MARK: - Dependencies

    private let breadcrumbStore: BreadcrumbStore
    private let deviceInfoProvider: DeviceInfoProvider

    // MARK: - Init

    public init(
        breadcrumbStore: BreadcrumbStore = .shared,
        deviceInfoProvider: DeviceInfoProvider = SystemDeviceInfoProvider()
    ) {
        self.breadcrumbStore = breadcrumbStore
        self.deviceInfoProvider = deviceInfoProvider
    }

    // MARK: - Public API

    /// Build and return the diagnostics bundle. Safe to call from any context.
    public func build(tenantSlug: String? = nil) async -> DiagnosticsBundle {
        let crumbs = await breadcrumbStore.recent(20)
        let entries = crumbs.map { crumb in
            DiagnosticsBundle.BreadcrumbEntry(
                timestamp: ISO8601DateFormatter().string(from: crumb.timestamp),
                level: crumb.level.rawValue,
                category: crumb.category,
                message: LogRedactor.redact(crumb.message)
            )
        }

        let info = deviceInfoProvider.currentInfo()
        return DiagnosticsBundle(
            appVersion: info.appVersion,
            buildNumber: info.buildNumber,
            iosVersion: info.iosVersion,
            deviceModel: info.deviceModel,
            tenantSlug: tenantSlug,
            recentBreadcrumbs: entries,
            networkSummary: "Last 20 breadcrumbs included. Detailed network logs redacted."
        )
    }

    /// Encode the bundle to a pretty-printed JSON `Data` attachment.
    public func buildJSONAttachment(tenantSlug: String? = nil) async throws -> Data {
        let bundle = await build(tenantSlug: tenantSlug)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }
}

// MARK: - DeviceInfoProvider

public protocol DeviceInfoProvider: Sendable {
    func currentInfo() -> DeviceInfo
}

public struct DeviceInfo: Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let iosVersion: String
    public let deviceModel: String

    public init(appVersion: String, buildNumber: String, iosVersion: String, deviceModel: String) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.iosVersion = iosVersion
        self.deviceModel = deviceModel
    }
}

public struct SystemDeviceInfoProvider: DeviceInfoProvider, Sendable {
    public init() {}

    public func currentInfo() -> DeviceInfo {
        #if canImport(UIKit)
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        #else
        let iosVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceModel = "Mac"
        #endif
        return DeviceInfo(
            appVersion: Platform.appVersion,
            buildNumber: Platform.buildNumber,
            iosVersion: iosVersion,
            deviceModel: deviceModel
        )
    }
}
