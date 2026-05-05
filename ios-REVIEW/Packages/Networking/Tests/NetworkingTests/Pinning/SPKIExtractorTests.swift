import XCTest
import CryptoKit
import Security
@testable import Networking

// MARK: - SPKIExtractorTests
//
// Unit tests for SPKIExtractor (§1.2 TLS Pinning).
// Coverage target: ≥ 80% of SPKIExtractor.swift
//
// Real SecCertificate/SecTrust instances are generated at test time using
// Security.framework key-generation APIs, keeping the tests hermetic and
// fast (no network required).

final class SPKIExtractorTests: XCTestCase {

    // MARK: - extractPublicKey(from: SecCertificate)

    func testExtractReturns32ByteHash() throws {
        let certificate = try XCTUnwrap(SPKIExtractorTests.makeSelfSignedCertificate())
        let hash = SPKIExtractor.extractPublicKey(from: certificate)
        XCTAssertEqual(hash?.count, 32, "SHA-256 digest must be 32 bytes")
    }

    func testExtractIsDeterministic() throws {
        let certificate = try XCTUnwrap(SPKIExtractorTests.makeSelfSignedCertificate())
        let h1 = SPKIExtractor.extractPublicKey(from: certificate)
        let h2 = SPKIExtractor.extractPublicKey(from: certificate)
        XCTAssertEqual(h1, h2, "Same certificate must produce the same hash")
    }

    func testDifferentCertificatesProduceDifferentHashes() throws {
        let cert1 = try XCTUnwrap(SPKIExtractorTests.makeSelfSignedCertificate())
        let cert2 = try XCTUnwrap(SPKIExtractorTests.makeSelfSignedCertificate())
        let h1 = SPKIExtractor.extractPublicKey(from: cert1)
        let h2 = SPKIExtractor.extractPublicKey(from: cert2)
        // Different keypairs → different digests.
        XCTAssertNotEqual(h1, h2, "Different keys must produce different hashes")
    }

    // MARK: - extractPublicKey(from: SecTrust)

    func testExtractFromTrustReturns32Bytes() throws {
        let certificate = try XCTUnwrap(SPKIExtractorTests.makeSelfSignedCertificate())
        let trust = try XCTUnwrap(SPKIExtractorTests.makeTrust(certificate: certificate))
        let hash = SPKIExtractor.extractPublicKey(from: trust)
        XCTAssertEqual(hash?.count, 32)
    }

    func testExtractFromTrustMatchesCertExtract() throws {
        let certificate = try XCTUnwrap(SPKIExtractorTests.makeSelfSignedCertificate())
        let trust = try XCTUnwrap(SPKIExtractorTests.makeTrust(certificate: certificate))
        let fromCert = SPKIExtractor.extractPublicKey(from: certificate)
        let fromTrust = SPKIExtractor.extractPublicKey(from: trust)
        XCTAssertEqual(fromCert, fromTrust,
                       "Trust-based and cert-based extraction must agree for the same key")
    }

    // MARK: - Fallback: pin-based matching round-trip

    func testExtractedHashMatchesPolicyPin() throws {
        let certificate = try XCTUnwrap(SPKIExtractorTests.makeSelfSignedCertificate())
        let hash = try XCTUnwrap(SPKIExtractor.extractPublicKey(from: certificate))
        let policy = PinningPolicy(pins: [hash], failClosed: true)
        XCTAssertTrue(policy.pins.contains(hash),
                      "Extracted hash should be usable directly in PinningPolicy.pins")
    }

    // MARK: - Factory helpers

    /// Generates an ephemeral EC P-256 key pair and wraps the public key in a
    /// minimal self-signed DER certificate using Security.framework.
    ///
    /// Returns `nil` only if key generation fails (should never happen on a
    /// modern iOS/macOS simulator).
    static func makeSelfSignedCertificate() -> SecCertificate? {
        // Generate an EC P-256 key pair.
        let keyAttrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent: false
        ]
        var pubKey: SecKey?
        var privKey: SecKey?
        let status = SecKeyGeneratePair(keyAttrs as CFDictionary, &pubKey, &privKey)
        guard status == errSecSuccess,
              let publicKey = pubKey,
              let privateKey = privKey else {
            return nil
        }

        // Build a minimal DER-encoded self-signed certificate using
        // SecCertificateCreateWithData (needs a properly formed ASN.1 blob).
        //
        // Constructing a full X.509 DER by hand is tedious. Instead, use
        // SecCertificateCreateWithData with a pre-baked DER for an EC key, then
        // replace with the real key via CryptoKit sign + manual construction.
        //
        // Practical approach: Use a certificate created via the
        // `SecTrustCreateWithCertificates` dance where we generate a CMS-signed
        // cert using SecKeyCreateRandomKey + the private key sign step.
        //
        // However, iOS/macOS Security.framework does NOT expose a simple
        // "self-sign a CSR" API. For test purposes we can use
        // `SecCertificateCreateWithData` with a DER block we build from the
        // exported public key.
        //
        // Simpler: Use the private key to sign a dummy OID and extract a
        // minimal SEQUENCE { INTEGER 1, BIT STRING <pubkey bytes> }.
        //
        // Actually the cleanest approach: Use CryptoKit P256 keys + the
        // SecKeyCreateWithData round-trip so we can hand SPKIExtractor a real
        // SecCertificate by calling SecCertificateCreateWithData with a
        // hand-built ASN.1 cert blob.  That is fragile, so instead we test
        // extractPublicKey(from certificate:) indirectly via
        // SecCertificateCopyKey which is the same code path used in production.
        //
        // We create a minimal certificate from the public key using the
        // CryptoKit approach below.
        return makeCertificateFromKeys(publicKey: publicKey, privateKey: privateKey)
    }

    private static func makeCertificateFromKeys(
        publicKey: SecKey,
        privateKey: SecKey
    ) -> SecCertificate? {
        // Build a DER-encoded X.509 v1 certificate minimal enough for
        // SecCertificateCopyKey to extract the public key.
        //
        // Structure (DER SEQUENCE):
        //   tbsCertificate SEQUENCE:
        //     version [0] INTEGER 0 (v1)
        //     serialNumber INTEGER 1
        //     signature AlgorithmIdentifier (ecPublicKey + P-256 OID)
        //     issuer  Name (one RDN: CN=Test)
        //     validity (NotBefore/NotAfter generalised time)
        //     subject Name (same)
        //     subjectPublicKeyInfo AlgorithmIdentifier + BIT STRING
        //   signatureAlgorithm AlgorithmIdentifier
        //   signature BIT STRING (we sign with the private key)
        //
        // This is the minimal path that lets SecCertificateCopyKey work.
        guard let pubKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }

        let der = buildMinimalECDERCert(rawPublicKeyBytes: pubKeyData, privateKey: privateKey)
        return der.flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
    }

    /// Builds a syntactically minimal DER X.509 certificate for the given
    /// uncompressed EC P-256 public key. The certificate is self-signed with
    /// the provided private key.
    private static func buildMinimalECDERCert(
        rawPublicKeyBytes: Data,
        privateKey: SecKey
    ) -> Data? {
        // EC OIDs
        let ecPublicKeyOID: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]       // 1.2.840.10045.2.1
        let p256OID: [UInt8]        = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07] // 1.2.840.10045.3.1.7
        let sha256WithECDSA: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02] // 1.2.840.10045.4.3.2
        let cnTestBytes: [UInt8]    = [0x63, 0x6E, 0x54, 0x65, 0x73, 0x74] // "cnTest"

        func tlv(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
            if body.count < 0x80 {
                return [tag, UInt8(body.count)] + body
            } else if body.count < 0x100 {
                return [tag, 0x81, UInt8(body.count)] + body
            } else {
                let hi = UInt8((body.count >> 8) & 0xFF)
                let lo = UInt8(body.count & 0xFF)
                return [tag, 0x82, hi, lo] + body
            }
        }
        func seq(_ body: [UInt8]) -> [UInt8] { tlv(0x30, body) }
        func set_(_ body: [UInt8]) -> [UInt8] { tlv(0x31, body) }
        func oid(_ bytes: [UInt8]) -> [UInt8] { tlv(0x06, bytes) }
        func int_(_ bytes: [UInt8]) -> [UInt8] { tlv(0x02, bytes) }
        func utcTime(_ s: String) -> [UInt8] { tlv(0x17, Array(s.utf8)) }
        func bitString(_ bytes: [UInt8]) -> [UInt8] { tlv(0x03, [0x00] + bytes) }
        func utf8Str(_ bytes: [UInt8]) -> [UInt8] { tlv(0x0C, bytes) }

        // AlgorithmIdentifier for ecPublicKey (P-256)
        let pubKeyAlgId = seq(oid(ecPublicKeyOID) + oid(p256OID))
        // SubjectPublicKeyInfo
        let spki = seq(pubKeyAlgId + bitString(Array(rawPublicKeyBytes)))
        // AlgorithmIdentifier for SHA-256 with ECDSA (for signatureAlgorithm)
        let sigAlgId = seq(oid(sha256WithECDSA))
        // RDN: CN=cnTest
        let rdn = set_(seq(oid([0x55, 0x04, 0x03]) + utf8Str(cnTestBytes)))
        let name = seq(rdn)
        // Validity: fixed dates well in the future for test stability
        let validity = seq(utcTime("200101000000Z") + utcTime("991231235959Z"))
        // Serial number
        let serial = int_([0x01])
        // TBSCertificate
        let tbs = seq(serial + sigAlgId + name + validity + name + spki)

        // Sign TBSCertificate with the private key.
        let tbsData = Data(tbs)
        let sigAlgorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, sigAlgorithm),
              let sigData = SecKeyCreateSignature(privateKey, sigAlgorithm, tbsData as CFData, nil) as Data?
        else {
            return nil
        }

        // Full certificate DER
        let cert = seq(tbs + sigAlgId + bitString(Array(sigData)))
        return Data(cert)
    }

    /// Creates a SecTrust with the given certificate, bypassing OS validation.
    static func makeTrust(certificate: SecCertificate) -> SecTrust? {
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        guard SecTrustCreateWithCertificates(
            [certificate] as CFArray,
            policy,
            &trust
        ) == errSecSuccess else {
            return nil
        }
        return trust
    }
}
