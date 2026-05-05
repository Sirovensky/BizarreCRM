import Foundation

// MARK: - DeepLink protocol seam

/// Abstraction for deep-linking into the DataImport or DataExport packages.
/// The app shell provides a concrete implementation at startup via
/// `DataBridgeDependencies.configure(...)`. Settings never imports those
/// packages directly.
public protocol DataBridgeDeepLink: Sendable {
    /// Navigate to the DataImport wizard / history screen.
    func openImport()
    /// Navigate to the DataExport wizard / schedule screen.
    func openExport()
}

// MARK: - ImportStatus summary seam

/// Summary of the most-recent import job. The app shell populates this by
/// observing ImportRepository without Settings importing DataImport directly.
public struct ImportSummary: Sendable, Equatable {
    public enum LastResult: Sendable, Equatable {
        case none
        case success(entityCount: Int, at: Date)
        case failure(reason: String, at: Date)
    }

    public let lastResult: LastResult
    public let activeJobCount: Int

    public init(lastResult: LastResult = .none, activeJobCount: Int = 0) {
        self.lastResult = lastResult
        self.activeJobCount = activeJobCount
    }
}

/// Protocol seam the app shell implements to provide import status to Settings.
public protocol ImportSummaryProvider: Sendable {
    func fetchSummary() async -> ImportSummary
}

// MARK: - ExportStatus summary seam

/// Summary of the most-recent export job and next scheduled run.
public struct ExportSummary: Sendable, Equatable {
    public enum LastResult: Sendable, Equatable {
        case none
        case success(at: Date)
        case failure(reason: String, at: Date)
    }

    public let lastResult: LastResult
    /// ISO-8601 string of the next scheduled export run, if any.
    public let nextScheduledRunAt: String?
    /// `true` while an export is in progress.
    public let isExporting: Bool

    public init(
        lastResult: LastResult = .none,
        nextScheduledRunAt: String? = nil,
        isExporting: Bool = false
    ) {
        self.lastResult = lastResult
        self.nextScheduledRunAt = nextScheduledRunAt
        self.isExporting = isExporting
    }
}

/// Protocol seam the app shell implements to provide export status to Settings.
public protocol ExportSummaryProvider: Sendable {
    func fetchSummary() async -> ExportSummary
}

// MARK: - Dependency bundle

/// Injected once at app startup. All three fields are optional so Settings
/// renders gracefully when the app shell hasn't wired them yet.
public struct DataBridgeDependencies: Sendable {
    public let deepLink: (any DataBridgeDeepLink)?
    public let importProvider: (any ImportSummaryProvider)?
    public let exportProvider: (any ExportSummaryProvider)?

    public init(
        deepLink: (any DataBridgeDeepLink)? = nil,
        importProvider: (any ImportSummaryProvider)? = nil,
        exportProvider: (any ExportSummaryProvider)? = nil
    ) {
        self.deepLink = deepLink
        self.importProvider = importProvider
        self.exportProvider = exportProvider
    }
}

// MARK: - Singleton holder (mirrors APIClientHolder pattern in SettingsView)

public enum DataBridgeHolder {
    nonisolated(unsafe) public static var current: DataBridgeDependencies = DataBridgeDependencies()
}
