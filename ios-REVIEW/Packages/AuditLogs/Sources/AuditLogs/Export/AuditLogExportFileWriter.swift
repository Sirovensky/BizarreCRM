import Foundation

/// Writes a CSV string to a uniquely-named temp file and returns the `URL`.
///
/// The file is placed in `FileManager.default.temporaryDirectory` and is
/// suitable for passing directly to `ShareLink(item:)` / `UIActivityViewController`.
///
/// Caller is responsible for cleaning up the file after the share sheet
/// is dismissed if long-lived temp storage is a concern; the OS also
/// purges the temp directory automatically between launches.
public enum AuditLogExportFileWriter {

    // MARK: - Errors

    public enum WriteError: LocalizedError {
        case encodingFailed
        case writeFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode CSV data as UTF-8."
            case .writeFailed(let underlying):
                return "Could not write export file: \(underlying.localizedDescription)"
            }
        }
    }

    // MARK: - Public interface

    /// Write `csvString` to a temp file named `audit-log-<timestamp>.csv`.
    ///
    /// - Parameter csvString: RFC-4180 CSV content to persist.
    /// - Returns: `URL` to the written file.
    /// - Throws: `WriteError` if encoding or disk write fails.
    @discardableResult
    public static func write(csvString: String) throws -> URL {
        guard let data = csvString.data(using: .utf8) else {
            throw WriteError.encodingFailed
        }
        let filename = "audit-log-\(timestampString()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw WriteError.writeFailed(underlying: error)
        }
        return url
    }

    // MARK: - Private helpers

    private static func timestampString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}
