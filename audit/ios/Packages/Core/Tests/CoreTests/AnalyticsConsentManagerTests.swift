import XCTest
@testable import Core

@MainActor
final class AnalyticsConsentManagerTests: XCTestCase {

    private var suiteName: String { "test.analytics.consent.\(name)" }

    private func makeSUT() -> AnalyticsConsentManager {
        // Each test gets its own UserDefaults suite for isolation
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AnalyticsConsentManager(defaults: defaults)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: — Default is opt-out

    func test_defaultState_isOptedOut() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isOptedIn, "Default must be opted-OUT (privacy-first)")
    }

    // MARK: — Opt-in persists

    func test_optIn_setsIsOptedInTrue() {
        let sut = makeSUT()
        sut.optIn()
        XCTAssertTrue(sut.isOptedIn)
    }

    func test_optOut_setsIsOptedInFalse() {
        let sut = makeSUT()
        sut.optIn()
        sut.optOut()
        XCTAssertFalse(sut.isOptedIn)
    }

    // MARK: — Persistence across instances

    func test_optIn_persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let sut1 = AnalyticsConsentManager(defaults: defaults)
        sut1.optIn()

        let sut2 = AnalyticsConsentManager(defaults: defaults)
        XCTAssertTrue(sut2.isOptedIn, "Opt-in should persist to new instance")
    }

    func test_optOut_persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let sut1 = AnalyticsConsentManager(defaults: defaults)
        sut1.optIn()
        sut1.optOut()

        let sut2 = AnalyticsConsentManager(defaults: defaults)
        XCTAssertFalse(sut2.isOptedIn, "Opt-out should persist to new instance")
    }

    // MARK: — Toggle

    func test_toggle_fromOptedOut_setsOptedIn() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isOptedIn)
        sut.toggle()
        XCTAssertTrue(sut.isOptedIn)
    }

    func test_toggle_fromOptedIn_setsOptedOut() {
        let sut = makeSUT()
        sut.optIn()
        sut.toggle()
        XCTAssertFalse(sut.isOptedIn)
    }

    // MARK: — Send is gated by consent

    func test_shouldSendEvents_whenOptedIn() {
        let sut = makeSUT()
        sut.optIn()
        XCTAssertTrue(sut.shouldSendEvents)
    }

    func test_shouldNotSendEvents_whenOptedOut() {
        let sut = makeSUT()
        XCTAssertFalse(sut.shouldSendEvents)
    }
}
