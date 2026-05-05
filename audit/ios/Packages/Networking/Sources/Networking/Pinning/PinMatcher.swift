import Foundation
import Security

/// Result of evaluating a server certificate chain against a ``PinningPolicy``.
public enum PinMatchResult: Sendable, Equatable {
    /// The SPKI hash of one of the chain certificates matched a pinned digest.
    case matched
    /// Pins are empty and ``PinningPolicy/allowBackupIfPinsEmpty`` is `true`.
    case allowedByBackup
    /// No certificate in the chain matched any pinned digest.
    case mismatch
    /// The trust object was invalid or key extraction failed for every cert.
    case extractionFailed
}

/// Pure-function matcher that evaluates a ``SecTrust`` chain against a
/// ``PinningPolicy``.
///
/// Checking the full chain (not just the leaf) lets operators pin an
/// intermediate CA key so that cert rotation by the leaf CA does not require
/// an app update.
///
/// Ownership: §1.2 TLS Pinning (iOS)
public enum PinMatcher {
    /// Evaluates whether the server chain satisfies the policy.
    ///
    /// - Parameters:
    ///   - trust: An evaluated ``SecTrust`` representing the server chain.
    ///   - policy: The ``PinningPolicy`` to check against.
    /// - Returns: A ``PinMatchResult`` describing the outcome.
    public static func evaluate(trust: SecTrust, against policy: PinningPolicy) -> PinMatchResult {
        // Fast path: no pins configured.
        if policy.pins.isEmpty {
            return policy.allowBackupIfPinsEmpty ? .allowedByBackup : .mismatch
        }

        // Walk the chain; a match on any certificate satisfies the policy.
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              !chain.isEmpty else {
            return .extractionFailed
        }

        var extractedAtLeastOne = false
        for certificate in chain {
            guard let hash = SPKIExtractor.extractPublicKey(from: certificate) else {
                continue
            }
            extractedAtLeastOne = true
            if policy.pins.contains(hash) {
                return .matched
            }
        }

        return extractedAtLeastOne ? .mismatch : .extractionFailed
    }

    /// Convenience: returns `true` if the connection should be allowed given
    /// the match result and the policy's ``PinningPolicy/failClosed`` flag.
    ///
    /// | Result            | failClosed=true | failClosed=false |
    /// |-------------------|-----------------|------------------|
    /// | matched           | ✓               | ✓                |
    /// | allowedByBackup   | ✓               | ✓                |
    /// | mismatch          | ✗               | ✓ (logged)       |
    /// | extractionFailed  | ✗               | ✓ (logged)       |
    public static func shouldAllow(result: PinMatchResult, policy: PinningPolicy) -> Bool {
        switch result {
        case .matched, .allowedByBackup:
            return true
        case .mismatch, .extractionFailed:
            return !policy.failClosed
        }
    }
}
