import Foundation

// MARK: - MmsSizeEstimator

/// Pure, stateless helper for estimating MMS total size and checking carrier limits.
/// No side effects — safe to call from tests without mocking.
public enum MmsSizeEstimator: Sendable {

    /// US carrier MMS size limit (1 600 KB = ~1.6 MB).
    /// Most US carriers enforce 300 KB–1.6 MB; we use the conservative common limit.
    public static let carrierLimitBytes: Int64 = 1_600_000

    // MARK: - Estimation

    /// Returns the sum of `sizeBytes` across all attachments.
    public static func estimateTotalBytes(attachments: [MmsAttachment]) -> Int64 {
        attachments.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Returns `true` when the total attachment size exceeds the carrier limit.
    public static func exceedsCarrierLimit(attachments: [MmsAttachment]) -> Bool {
        estimateTotalBytes(attachments: attachments) > carrierLimitBytes
    }

    /// Returns a user-facing warning string if the total exceeds the carrier limit,
    /// `nil` otherwise.
    public static func warningMessage(attachments: [MmsAttachment]) -> String? {
        let total = estimateTotalBytes(attachments: attachments)
        guard total > carrierLimitBytes else { return nil }
        let totalStr = formattedSize(bytes: total)
        let limitStr = formattedSize(bytes: carrierLimitBytes)
        return "Total attachment size (\(totalStr)) exceeds the carrier limit (\(limitStr)). Some carriers may reject this message."
    }

    // MARK: - Formatting

    /// Human-readable byte count string (KB or MB).
    public static func formattedSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: bytes)
    }
}
