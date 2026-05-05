import XCTest
@testable import Auth

// MARK: - Signup types tests

final class SignupEndpointsTests: XCTestCase {

    // MARK: - ShopType

    func test_shopType_allCasesHaveDisplayNames() {
        for type in ShopType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "ShopType.\(type.rawValue) has no display name")
        }
    }

    func test_shopType_allCasesHaveIcons() {
        for type in ShopType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "ShopType.\(type.rawValue) has no icon")
        }
    }

    func test_shopType_rawValuesRoundTrip() throws {
        for type in ShopType.allCases {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(ShopType.self, from: encoded)
            XCTAssertEqual(decoded, type)
        }
    }

    // MARK: - SignupRequest encoding

    func test_signupRequest_encodesCorrectCodingKeys() throws {
        let req = SignupRequest(
            username: "jsmith",
            password: "p@ssw0rd!",
            email: "j@example.com",
            firstName: "Jane",
            lastName: "Smith",
            storeName: "My Shop",
            shopType: .repair,
            timezone: "America/New_York",
            setupToken: "tkn-abc"
        )
        let data = try JSONEncoder().encode(req)
        let dict = try JSONDecoder().decode([String: String].self, from: data)

        XCTAssertEqual(dict["username"], "jsmith")
        XCTAssertNil(dict["password"], "password should not decode to String — security check")
        XCTAssertEqual(dict["first_name"], "Jane")
        XCTAssertEqual(dict["last_name"], "Smith")
        XCTAssertEqual(dict["store_name"], "My Shop")
        XCTAssertEqual(dict["timezone"], "America/New_York")
        XCTAssertEqual(dict["setup_token"], "tkn-abc")
    }

    // MARK: - SignupResponse decoding

    func test_signupResponse_withAccessToken_autoLoginTrue() throws {
        let json = """
        {"accessToken": "tok-abc", "refreshToken": "ref-xyz", "message": null}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(SignupResponse.self, from: json)
        XCTAssertTrue(resp.autoLogin)
        XCTAssertEqual(resp.accessToken, "tok-abc")
    }

    func test_signupResponse_withoutAccessToken_autoLoginFalse() throws {
        let json = """
        {"accessToken": null, "refreshToken": null, "message": "Check your email"}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(SignupResponse.self, from: json)
        XCTAssertFalse(resp.autoLogin)
    }
}
