import Foundation

// §34 Crisis Recovery helpers — RecoveryReport
// Writes a JSON snapshot to device for support diagnostics (no PII).

/// An immutable JSON-serialisable snapshot written to the device for offline
/// support diagnostics.
///
/// **Privacy guarantee**: this struct intentionally omits all PII fields.
/// - No user names, emails, phone numbers, or account IDs.
/// - `tenantSlug` is a business-level identifier chosen by the tenant.
/// - `userRole` is a role label, never a user ID.
/// - `safeMode*` and `crisisMode*` fields are booleans / enum raw values.
public struct RecoveryReport: Codable, Sendable {

    // MARK: — App context

    /// Short marketing version string (e.g. "1.3.0").
    public let appVersion: String
    /// Build number (e.g. "78").
    public let appBuild: String
    /// iOS version string (e.g. "17.4").
    public let iOSVersion: String
    /// Hardware model identifier (e.g. "iPhone16,2").
    public let device: String

    // MARK: — Tenant context (no PII)

    public let tenantSlug: String
    public let userRole: String

    // MARK: — Crisis state

    public let isCrisisModeActive: Bool
    public let crisisModeActivatedAt: Date?

    public let isSafeModeActive: Bool
    public let safeModeReason: String?
    public let safeModeActivatedAt: Date?

    // MARK: — Crash-loop context

    /// Number of recent launches recorded by `CrashLoopDetector` in its window.
    public let recentLaunchCount: Int
    /// `true` if a crash loop was detected.
    public let crashLoopDetected: Bool

    // MARK: — Timestamp

    /// When this report was generated (UTC).
    public let generatedAt: Date

    public init(
        appVersion: String,
        appBuild: String,
        iOSVersion: String,
        device: String,
        tenantSlug: String,
        userRole: String,
        isCrisisModeActive: Bool,
        crisisModeActivatedAt: Date?,
        isSafeModeActive: Bool,
        safeModeReason: String?,
        safeModeActivatedAt: Date?,
        recentLaunchCount: Int,
        crashLoopDetected: Bool,
        generatedAt: Date = Date()
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.iOSVersion = iOSVersion
        self.device = device
        self.tenantSlug = tenantSlug
        self.userRole = userRole
        self.isCrisisModeActive = isCrisisModeActive
        self.crisisModeActivatedAt = crisisModeActivatedAt
        self.isSafeModeActive = isSafeModeActive
        self.safeModeReason = safeModeReason
        self.safeModeActivatedAt = safeModeActivatedAt
        self.recentLaunchCount = recentLaunchCount
        self.crashLoopDetected = crashLoopDetected
        self.generatedAt = generatedAt
    }
}

// MARK: — Writer

/// Writes `RecoveryReport` snapshots to the device's Caches directory as JSON files.
///
/// Files are named `recovery-<ISO8601 timestamp>.json` and placed in
/// `<Caches>/com.bizarrecrm/recovery/`. The directory is created on first write.
///
/// Support staff can retrieve reports via Files.app or the Xcode Devices window.
/// Older reports beyond `maxStoredReports` are pruned automatically.
public final class RecoveryReportWriter: @unchecked Sendable {

    // MARK: — Singleton

    public static let shared = RecoveryReportWriter()

    // MARK: — Configuration

    /// Maximum number of report files to keep on device. Default: 10.
    public let maxStoredReports: Int

    private let fileManager: FileManager
    private let encoder: JSONEncoder

    // MARK: — Init

    public init(
        maxStoredReports: Int = 10,
        fileManager: FileManager = .default
    ) {
        self.maxStoredReports = maxStoredReports
        self.fileManager = fileManager
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
    }

    // MARK: — Public API

    /// Write `report` to disk as JSON.
    ///
    /// - Returns: The URL of the written file, or `nil` if writing failed.
    @discardableResult
    public func write(_ report: RecoveryReport) -> URL? {
        guard let dir = recoveryDirectory() else { return nil }
        let fileName = "recovery-\(isoTimestamp(report.generatedAt)).json"
        let fileURL = dir.appendingPathComponent(fileName)
        guard let data = try? encoder.encode(report) else { return nil }
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return nil }
        pruneOldReports(in: dir)
        return fileURL
    }

    /// Returns URLs of all stored recovery reports, sorted oldest-first.
    public func allReportURLs() -> [URL] {
        guard let dir = recoveryDirectory() else { return [] }
        let urls = (try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("recovery-") }
            .sorted { ($0.lastPathComponent) < ($1.lastPathComponent) }
    }

    /// Delete all stored recovery reports.
    public func deleteAll() {
        guard let dir = recoveryDirectory() else { return }
        let urls = allReportURLs()
        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: — Private helpers

    private func recoveryDirectory() -> URL? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches
            .appendingPathComponent("com.bizarrecrm", isDirectory: true)
            .appendingPathComponent("recovery", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func pruneOldReports(in dir: URL) {
        let existing = allReportURLs()
        guard existing.count > maxStoredReports else { return }
        let toDelete = existing.prefix(existing.count - maxStoredReports)
        for url in toDelete {
            try? fileManager.removeItem(at: url)
        }
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "Z")
    }
}

// MARK: — Convenience builder

extension RecoveryReport {

    // MARK: — Platform helper

    /// Returns the current OS version string without requiring UIKit import inside a function.
    static func systemVersion() -> String {
        #if os(iOS) || os(tvOS)
        // Inline the UIDevice call via the bridging approach below —
        // UIKit is available in this module when compiled for iOS.
        return ProcessInfo.processInfo.operatingSystemVersionString
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    /// Build a report from the current live app state.
    ///
    /// - Parameters:
    ///   - tenantSlug: Business-level identifier from the active session.
    ///   - userRole: Role of the authenticated user.
    ///   - crisisMode: `CrisisMode` instance (defaults to `.shared`).
    ///   - safeMode: `SafeMode` instance (defaults to `.shared`).
    ///   - detector: `CrashLoopDetector` instance (defaults to `.shared`).
    @MainActor
    public static func current(
        tenantSlug: String,
        userRole: String,
        crisisMode: CrisisMode = .shared,
        safeMode: SafeMode = .shared,
        detector: CrashLoopDetector = .shared
    ) -> RecoveryReport {
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        var sysinfo = utsname()
        uname(&sysinfo)
        let device = withUnsafeBytes(of: &sysinfo.machine) { ptr in
            let bytes = ptr.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }

        let iOSVersion = RecoveryReport.systemVersion()

        return RecoveryReport(
            appVersion: appVersion,
            appBuild: appBuild,
            iOSVersion: iOSVersion,
            device: device,
            tenantSlug: tenantSlug,
            userRole: userRole,
            isCrisisModeActive: crisisMode.isActive,
            crisisModeActivatedAt: crisisMode.activatedAt,
            isSafeModeActive: safeMode.isActive,
            safeModeReason: safeMode.reason?.rawValue,
            safeModeActivatedAt: safeMode.activatedAt,
            recentLaunchCount: detector.recentLaunchCount(),
            crashLoopDetected: detector.isLooping()
        )
    }
}
