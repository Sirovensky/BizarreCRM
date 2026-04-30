import Testing
@testable import Setup

// MARK: - §36.5 Network Diagnostics Tests

struct NetworkDiagnosticStatusTests {

    // MARK: - isCaptivePortal

    @Test func captivePortalWithURL() {
        let url = URL(string: "http://captive.example.com")!
        let status = NetworkDiagnosticStatus.captivePortalDetected(portalURL: url)
        #expect(status.isCaptivePortal == true)
        #expect(status.isVPN == false)
        #expect(status.isOK == false)
    }

    @Test func captivePortalWithoutURL() {
        let status = NetworkDiagnosticStatus.captivePortalDetected(portalURL: nil)
        #expect(status.isCaptivePortal == true)
    }

    // MARK: - isVPN

    @Test func vpnDetected() {
        let status = NetworkDiagnosticStatus.vpnDetected
        #expect(status.isVPN == true)
        #expect(status.isCaptivePortal == false)
        #expect(status.isOK == false)
    }

    // MARK: - isOK

    @Test func okStatus() {
        #expect(NetworkDiagnosticStatus.ok.isOK == true)
        #expect(NetworkDiagnosticStatus.ok.isCaptivePortal == false)
        #expect(NetworkDiagnosticStatus.ok.isVPN == false)
    }

    // MARK: - icons / colors (smoke test — no crash)

    @Test func allCasesHaveIcon() {
        let cases: [NetworkDiagnosticStatus] = [
            .unknown, .checking, .ok,
            .captivePortalDetected(portalURL: nil),
            .vpnDetected,
            .failed(reason: "test")
        ]
        for status in cases {
            #expect(!status.icon.isEmpty, "Icon string should not be empty for \(status)")
        }
    }

    // MARK: - Equality

    @Test func equalityOK() {
        #expect(NetworkDiagnosticStatus.ok == .ok)
    }

    @Test func equalityFailed() {
        #expect(NetworkDiagnosticStatus.failed(reason: "a") == .failed(reason: "a"))
        #expect(NetworkDiagnosticStatus.failed(reason: "a") != .failed(reason: "b"))
    }
}
