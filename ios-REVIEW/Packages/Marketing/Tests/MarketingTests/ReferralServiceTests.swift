import Testing
import Foundation
@testable import Marketing

@Suite("ReferralService")
struct ReferralServiceTests {

    // MARK: - Code generation

    @Test("getOrGenerateCode returns code from API")
    func getOrGenerateCode() async throws {
        let mock = MockAPIClient()
        let expectedCode = ReferralCode(
            id: "rc1",
            customerId: "cust1",
            code: "ABC12345",
            createdAt: Date(),
            uses: 0,
            conversions: 0
        )
        await mock.setReferralCodeResult(.success(expectedCode))
        let service = ReferralService(api: mock)
        let code = try await service.getOrGenerateCode(customerId: "cust1")
        #expect(code.id == "rc1")
        #expect(code.code == "ABC12345")
        #expect(code.customerId == "cust1")
    }

    @Test("getOrGenerateCode propagates API error")
    func getOrGenerateCodeError() async {
        let mock = MockAPIClient()
        await mock.setReferralCodeResult(.failure(URLError(.notConnectedToInternet)))
        let service = ReferralService(api: mock)
        do {
            _ = try await service.getOrGenerateCode(customerId: "cust1")
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is URLError)
        }
    }

    @Test("getOrGenerateCode calls correct API path")
    func getOrGenerateCodePath() async throws {
        let mock = MockAPIClient()
        let code = ReferralCode(id: "r1", customerId: "cX", code: "XY123456", createdAt: Date(), uses: 0, conversions: 0)
        await mock.setReferralCodeResult(.success(code))
        let service = ReferralService(api: mock)
        _ = try await service.getOrGenerateCode(customerId: "cX")
        let lastPath = await mock.lastGetPath
        #expect(lastPath == "referrals/code/cX")
    }

    // MARK: - Share link

    @Test("generateShareLink produces bizarrecrm deep link")
    func generateShareLinkDeep() async {
        let service = ReferralService(api: MockAPIClient())
        let url = await service.generateShareLink(code: "TESTCODE")
        #expect(url.absoluteString.contains("TESTCODE"))
        // Primary URL is the web fallback (universal link); deep link is embedded
        #expect(url.absoluteString.contains("bizarrecrm"))
    }

    @Test("generateShareLink web fallback is https")
    func generateShareLinkHTTPS() async {
        let service = ReferralService(api: MockAPIClient())
        let url = await service.generateShareLink(code: "ABCD1234")
        #expect(url.scheme == "https")
    }

    // MARK: - QR code

    // QR generation requires UIKit which is only available on iOS/iPadOS
    #if canImport(UIKit)
    @Test("generateQR returns non-nil image")
    func generateQR() async {
        let service = ReferralService(api: MockAPIClient())
        let image = await service.generateQR(code: "ABCD1234")
        #expect(image != nil)
    }
    #endif
}
