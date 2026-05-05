import Foundation
import Security
import CryptoKit

/// Pure-function SPKI hash extractor.
///
/// Derives the SHA-256 digest of the DER-encoded SubjectPublicKeyInfo blob
/// from a ``SecTrust`` evaluation result. The result matches the wire format
/// used by ``PinningPolicy/pins`` and ``PinMatcher``.
///
/// Ownership: §1.2 TLS Pinning (iOS)
public enum SPKIExtractor {
    // MARK: - Trust-based extraction

    /// Extracts the SHA-256 hash of the leaf certificate's public key SPKI
    /// from an evaluated ``SecTrust``.
    ///
    /// The implementation uses `SecTrustCopyKey` (iOS 14+) to retrieve the
    /// ``SecKey`` and then `SecKeyCopyExternalRepresentation` to get the raw
    /// DER bytes. The SHA-256 digest is computed over those bytes.
    ///
    /// - Parameter trust: An already-evaluated ``SecTrust`` object. The caller
    ///   is responsible for running `SecTrustEvaluateWithError` before calling
    ///   this function.
    /// - Returns: The 32-byte SHA-256 digest, or `nil` if extraction fails.
    public static func extractPublicKey(from trust: SecTrust) -> Data? {
        guard let secKey = SecTrustCopyKey(trust) else { return nil }
        return publicKeyHash(from: secKey)
    }

    // MARK: - Certificate-based extraction

    /// Extracts the SHA-256 hash of a certificate's public key SPKI.
    ///
    /// Useful for pre-computing pins offline (e.g. in unit tests) without
    /// constructing a full ``SecTrust``.
    ///
    /// - Parameter certificate: A ``SecCertificate`` value.
    /// - Returns: The 32-byte SHA-256 digest, or `nil` if extraction fails.
    public static func extractPublicKey(from certificate: SecCertificate) -> Data? {
        guard let secKey = SecCertificateCopyKey(certificate) else { return nil }
        return publicKeyHash(from: secKey)
    }

    // MARK: - Private helpers

    private static func publicKeyHash(from secKey: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(secKey, &error) as Data? else {
            return nil
        }
        let digest = SHA256.hash(data: keyData)
        return Data(digest)
    }
}
