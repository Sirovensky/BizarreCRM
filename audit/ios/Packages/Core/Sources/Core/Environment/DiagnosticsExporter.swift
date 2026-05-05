import Foundation

// §77 Environment & Build Flavor helpers
// DiagnosticsExporter — writes a JSON snapshot of the current environment,
// feature-flag states, and safe device metadata for bug reports.
//
// PII exclusions (never written):
//   - No user name, email, phone, or auth tokens
//   - No device name (contains the owner's real name on most devices)
//   - No IP address, location, or carrier name
//   - No IDFA / advertising identifier
//
// The output is a self-contained JSON file that can be attached to a Jira
// ticket or emailed without privacy review.

// MARK: - DiagnosticsSnapshot

/// Pure-value snapshot of diagnostics metadata.
public struct DiagnosticsSnapshot: Codable, Equatable, Sendable {

    // MARK: Nested types

    public struct EnvironmentInfo: Codable, Equatable, Sendable {
        public let flavor: String
        public let appVersion: String
        public let buildNumber: String
        public let bundleIdentifier: String
    }

    public struct DeviceInfo: Codable, Equatable, Sendable {
        public let systemName: String
        public let systemVersion: String
        public let model: String          // "iPhone", "iPad", "Mac" — not device name
        public let isSimulator: Bool
    }

    // MARK: Properties

    /// ISO-8601 UTC timestamp of when the snapshot was taken.
    public let capturedAt: String
    public let environment: EnvironmentInfo
    public let device: DeviceInfo
    /// Effective values for every known feature flag.
    public let featureFlags: [String: Bool]
}

// MARK: - DiagnosticsExporter

/// Creates and optionally persists a `DiagnosticsSnapshot` as JSON.
public struct DiagnosticsExporter: Sendable {

    // MARK: - Dependencies

    private let resolver: FeatureFlagResolver
    private let flavor: BuildFlavor
    private let deviceInfoProvider: DeviceInfoProviding
    private let dateProvider: @Sendable () -> Date

    // MARK: - Init

    /// Creates the exporter with production defaults.
    public init(
        resolver: FeatureFlagResolver = FeatureFlagResolver(),
        flavor: BuildFlavor = .current,
        deviceInfoProvider: DeviceInfoProviding = SystemDeviceInfo(),
        dateProvider: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.resolver = resolver
        self.flavor = flavor
        self.deviceInfoProvider = deviceInfoProvider
        self.dateProvider = dateProvider
    }

    // MARK: - Public API

    /// Builds a `DiagnosticsSnapshot` for the current runtime state.
    public func makeSnapshot() -> DiagnosticsSnapshot {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return DiagnosticsSnapshot(
            capturedAt: formatter.string(from: dateProvider()),
            environment: DiagnosticsSnapshot.EnvironmentInfo(
                flavor: flavor.rawValue,
                appVersion: Platform.appVersion,
                buildNumber: Platform.buildNumber,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown"
            ),
            device: DiagnosticsSnapshot.DeviceInfo(
                systemName: deviceInfoProvider.systemName,
                systemVersion: deviceInfoProvider.systemVersion,
                model: deviceInfoProvider.model,
                isSimulator: deviceInfoProvider.isSimulator
            ),
            featureFlags: resolver.snapshot()
        )
    }

    /// Serialises the snapshot to pretty-printed JSON data.
    ///
    /// - Throws: `EncodingError` if JSON encoding fails (practically never).
    public func exportJSON() throws -> Data {
        let snapshot = makeSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Writes the JSON snapshot to `url` on disk.
    ///
    /// - Parameter url: Destination file URL (typically in the Caches directory).
    /// - Throws: File-write or encoding errors.
    public func write(to url: URL) throws {
        let data = try exportJSON()
        try data.write(to: url, options: .atomic)
    }

    /// Convenience: writes to `<Caches>/diagnostics-<timestamp>.json`
    /// and returns the URL.
    ///
    /// - Throws: File-write or encoding errors.
    @discardableResult
    public func writeToCache() throws -> URL {
        let timestamp = Int(dateProvider().timeIntervalSince1970)
        let filename = "diagnostics-\(timestamp).json"
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        try write(to: url)
        return url
    }
}

// MARK: - DeviceInfoProviding

/// Abstraction over platform device information, so the exporter can be
/// tested without UIDevice or ProcessInfo.
public protocol DeviceInfoProviding: Sendable {
    var systemName: String { get }
    var systemVersion: String { get }
    /// Human-readable model family ("iPhone", "iPad", "Mac", "Simulator").
    var model: String { get }
    var isSimulator: Bool { get }
}

// MARK: - SystemDeviceInfo

/// Production implementation that reads from `ProcessInfo` and compile-time
/// constants. Does NOT use `UIDevice.current.name` (PII).
public struct SystemDeviceInfo: DeviceInfoProviding, Sendable {
    public init() {}

    public var systemName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "unknown"
        #endif
    }

    public var systemVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    public var model: String {
        if isSimulator { return "Simulator" }
        #if os(iOS)
        // Return generic family, never the specific model string that
        // could be used for fingerprinting.
        #if targetEnvironment(macCatalyst)
        return "Mac"
        #else
        // Use ProcessInfo machine string if available, otherwise generic
        return "iOS Device"
        #endif
        #elseif os(macOS)
        return "Mac"
        #else
        return "unknown"
        #endif
    }

    public var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
