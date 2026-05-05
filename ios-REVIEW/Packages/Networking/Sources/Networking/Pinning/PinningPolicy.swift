import Foundation

/// Immutable value type describing a TLS public-key pinning policy for a
/// single base URL. Holds the set of trusted SPKI SHA-256 digests (raw Data,
/// not base64) and the fail-closed/open behaviour.
///
/// Ownership: §1.2 TLS Pinning (iOS)
public struct PinningPolicy: Sendable, Equatable {
    /// SHA-256 digests of the DER-encoded SubjectPublicKeyInfo blobs for all
    /// trusted keys. Use ``SPKIExtractor`` to derive these from a live
    /// ``SecTrust`` or pre-compute them offline.
    public let pins: Set<Data>

    /// When `true` and ``pins`` is empty the connection is allowed through
    /// (trust the OS chain, no pinning). When `false` an empty pin set
    /// blocks everything — useful to "disable" a tenant during an incident.
    public let allowBackupIfPinsEmpty: Bool

    /// When `true` (default) a pin mismatch cancels the challenge. When
    /// `false` the mismatch is logged but the connection proceeds — useful
    /// in dev/staging against Let's Encrypt staging certs.
    public let failClosed: Bool

    public init(
        pins: Set<Data>,
        allowBackupIfPinsEmpty: Bool = true,
        failClosed: Bool = true
    ) {
        self.pins = pins
        self.allowBackupIfPinsEmpty = allowBackupIfPinsEmpty
        self.failClosed = failClosed
    }

    // MARK: - Convenience

    /// A policy with no pins and `allowBackupIfPinsEmpty = true`. Effectively
    /// disables pinning — the OS certificate chain is trusted as-is.
    public static let noPinning = PinningPolicy(
        pins: [],
        allowBackupIfPinsEmpty: true,
        failClosed: false
    )
}
