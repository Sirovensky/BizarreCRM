import Foundation

// MARK: - BackupError

/// Errors produced by `BackupManager`.
public enum BackupError: Error, Sendable, LocalizedError {
    /// The supplied passphrase could not decrypt the backup file.
    case invalidPassphrase
    /// The backup was encrypted with a different schema version.
    case schemaMismatch(local: Int, backup: Int)
    /// The backup file is corrupted or not a valid BizarreCRM backup.
    case corrupt
    /// An underlying I/O or file-system error.
    case ioError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidPassphrase:
            return "Incorrect passphrase. Please try again."
        case .schemaMismatch(let local, let backup):
            return "Schema version mismatch (device: \(local), backup: \(backup)). "
                + "Update the app before restoring this backup."
        case .corrupt:
            return "The backup file appears to be corrupted or is not a BizarreCRM backup."
        case .ioError(let underlying):
            return "I/O error: \(underlying.localizedDescription)"
        }
    }
}
