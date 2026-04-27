import Testing
@testable import Auth

// MARK: - §2.13 PIN Blocklist Tests

struct PINBlocklistTests {

    // MARK: - All-same digit

    @Test func allSameDigitFourChars() {
        for d in 0...9 {
            let pin = String(repeating: "\(d)", count: 4)
            let violation = PINBlocklist.check(pin: pin)
            #expect(violation == .allSameDigit, "Expected .allSameDigit for \(pin)")
        }
    }

    @Test func allSameDigitSixChars() {
        let pin = "777777"
        #expect(PINBlocklist.check(pin: pin) == .allSameDigit)
    }

    // MARK: - Sequential ascending

    @Test func sequentialAscendingFour() {
        #expect(PINBlocklist.check(pin: "1234") == .sequentialAscending)
        #expect(PINBlocklist.check(pin: "2345") == .sequentialAscending)
        #expect(PINBlocklist.check(pin: "0123") == .sequentialAscending)
    }

    @Test func sequentialAscendingSix() {
        #expect(PINBlocklist.check(pin: "123456") == .sequentialAscending)
        #expect(PINBlocklist.check(pin: "234567") == .sequentialAscending)
    }

    // MARK: - Sequential descending

    @Test func sequentialDescendingFour() {
        #expect(PINBlocklist.check(pin: "9876") == .sequentialDescending)
        #expect(PINBlocklist.check(pin: "8765") == .sequentialDescending)
    }

    @Test func sequentialDescendingSix() {
        #expect(PINBlocklist.check(pin: "654321") == .sequentialDescending)
    }

    // MARK: - Known common patterns

    @Test func knownCommonYear() {
        #expect(PINBlocklist.check(pin: "2024") != nil)
        #expect(PINBlocklist.check(pin: "2025") != nil)
        #expect(PINBlocklist.check(pin: "1999") != nil)
    }

    @Test func knownCommonMirror() {
        #expect(PINBlocklist.check(pin: "1212") != nil)
        #expect(PINBlocklist.check(pin: "1122") != nil)
    }

    // MARK: - Allowed PINs

    @Test func allowedRandomPins() {
        #expect(PINBlocklist.check(pin: "2847") == nil)
        #expect(PINBlocklist.check(pin: "9301") == nil)
        #expect(PINBlocklist.check(pin: "481729") == nil)
        #expect(PINBlocklist.check(pin: "5839") == nil)
    }

    // MARK: - Edge cases

    @Test func emptyStringReturnsNil() {
        #expect(PINBlocklist.check(pin: "") == nil)
    }

    @Test func singleDigitAllowed() {
        #expect(PINBlocklist.check(pin: "5") == nil)
    }

    @Test func nonDigitsIgnored() {
        // Should not crash or incorrectly flag
        #expect(PINBlocklist.check(pin: "abcd") == nil)
    }

    // MARK: - isBlocked helper

    @Test func isBlockedMirrorsCheck() {
        #expect(PINBlocklist.isBlocked("0000") == true)
        #expect(PINBlocklist.isBlocked("2847") == false)
    }
}
