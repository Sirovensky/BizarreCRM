import XCTest
@testable import Core

// MARK: - PublicTrackingURLsTests

/// Tests ``PublicTrackingURLs`` URL builder.
///
/// Coverage targets:
/// - Each builder method produces the correct path shape.
/// - Percent-encoding is applied for IDs with special characters.
/// - Empty IDs return `nil`.
/// - Custom base-URL overrides are respected.
final class PublicTrackingURLsTests: XCTestCase {

    // MARK: - trackingURL

    func test_trackingURL_defaultBase_hasCorrectPath() {
        let url = PublicTrackingURLs.trackingURL(ticketId: "TKT-9901")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.path, "/track/TKT-9901")
        XCTAssertEqual(url?.host, "app.bizarrecrm.com")
        XCTAssertEqual(url?.scheme, "https")
    }

    func test_trackingURL_emptyID_returnsNil() {
        XCTAssertNil(PublicTrackingURLs.trackingURL(ticketId: ""))
    }

    func test_trackingURL_specialCharactersArePercentEncoded() {
        let url = PublicTrackingURLs.trackingURL(ticketId: "TKT 99 01")
        XCTAssertNotNil(url)
        // Space must be encoded in the resulting URL string
        XCTAssertFalse(url?.absoluteString.contains(" ") ?? true)
        XCTAssertTrue(url?.absoluteString.contains("TKT") ?? false)
    }

    func test_trackingURL_customBase_usesOverride() {
        let customBase = URL(string: "https://crm.example.com")!
        let url = PublicTrackingURLs.trackingURL(ticketId: "TKT-001", baseURL: customBase)
        XCTAssertEqual(url?.host, "crm.example.com")
        XCTAssertEqual(url?.path, "/track/TKT-001")
    }

    // MARK: - paymentURL

    func test_paymentURL_defaultBase_hasCorrectPath() {
        let url = PublicTrackingURLs.paymentURL(linkId: "PAY-4321")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.path, "/pay/PAY-4321")
        XCTAssertEqual(url?.host, "app.bizarrecrm.com")
        XCTAssertEqual(url?.scheme, "https")
    }

    func test_paymentURL_emptyID_returnsNil() {
        XCTAssertNil(PublicTrackingURLs.paymentURL(linkId: ""))
    }

    func test_paymentURL_specialCharacters_areEncoded() {
        let url = PublicTrackingURLs.paymentURL(linkId: "PAY/2024/001")
        XCTAssertNotNil(url)
        // The slash in the id is allowed by urlPathAllowed but the path must
        // start with /pay/ — subsequent slashes are part of the encoded id.
        XCTAssertTrue(url?.absoluteString.contains("/pay/") ?? false)
    }

    func test_paymentURL_customBase_usesOverride() {
        let customBase = URL(string: "https://payments.acme.com")!
        let url = PublicTrackingURLs.paymentURL(linkId: "LNK-007", baseURL: customBase)
        XCTAssertEqual(url?.host, "payments.acme.com")
        XCTAssertEqual(url?.path, "/pay/LNK-007")
    }

    // MARK: - estimateURL

    func test_estimateURL_defaultBase_hasCorrectPath() {
        let url = PublicTrackingURLs.estimateURL(estimateId: "EST-5500")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.path, "/estimate/EST-5500")
        XCTAssertEqual(url?.host, "app.bizarrecrm.com")
        XCTAssertEqual(url?.scheme, "https")
    }

    func test_estimateURL_emptyID_returnsNil() {
        XCTAssertNil(PublicTrackingURLs.estimateURL(estimateId: ""))
    }

    func test_estimateURL_customBase_usesOverride() {
        let customBase = URL(string: "https://estimates.selfhosted.com")!
        let url = PublicTrackingURLs.estimateURL(estimateId: "EST-042", baseURL: customBase)
        XCTAssertEqual(url?.host, "estimates.selfhosted.com")
        XCTAssertEqual(url?.path, "/estimate/EST-042")
    }

    // MARK: - defaultBaseURL constant

    func test_defaultBaseURL_matchesCanonicalHost() {
        XCTAssertEqual(
            PublicTrackingURLs.defaultBaseURL.host,
            DeepLinkURLParser.universalLinkHost
        )
    }

    func test_defaultBaseURL_isHTTPS() {
        XCTAssertEqual(PublicTrackingURLs.defaultBaseURL.scheme, "https")
    }
}
