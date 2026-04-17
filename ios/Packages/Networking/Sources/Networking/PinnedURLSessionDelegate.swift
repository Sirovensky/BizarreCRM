import Foundation
import CryptoKit
import Core

/// SPKI pinning — hashes the server's public key and compares against a
/// bundled set. Pinning the key (not the cert) lets us rotate certs without
/// shipping app updates, as long as the underlying key stays the same.
///
/// See howtoIOS.md §11 and Appendix A2.
public final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let pinnedSPKIBase64: Set<String>
    private let enforce: Bool

    /// - Parameters:
    ///   - pinnedSPKIBase64: base64 SHA-256 hashes of DER-encoded public keys.
    ///   - enforce: when `false`, logs mismatches but permits the connection.
    ///     Useful for local dev against Let's Encrypt staging; never in prod.
    public init(pinnedSPKIBase64: Set<String>, enforce: Bool = true) {
        self.pinnedSPKIBase64 = pinnedSPKIBase64
        self.enforce = enforce
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil) else {
            AppLog.networking.error("TLS trust evaluation failed for \(challenge.protectionSpace.host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if pinnedSPKIBase64.isEmpty {
            // No pins configured (e.g. CA-trusted Let's Encrypt path without pinning).
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        guard
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
            let leaf = chain.first,
            let publicKey = SecCertificateCopyKey(leaf),
            let pubData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else {
            AppLog.networking.error("Could not extract public key from leaf cert")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let digest = SHA256.hash(data: pubData)
        let computed = Data(digest).base64EncodedString()

        if pinnedSPKIBase64.contains(computed) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        AppLog.networking.error("SPKI mismatch — expected one of \(pinnedSPKIBase64, privacy: .public), got \(computed, privacy: .public)")
        if enforce {
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }
}
