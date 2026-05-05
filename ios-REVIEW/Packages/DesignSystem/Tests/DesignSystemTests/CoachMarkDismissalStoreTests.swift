import Testing
import Foundation
@testable import DesignSystem

// §68 — CoachMarkDismissalStore tests

@Suite("CoachMarkDismissalStore")
struct CoachMarkDismissalStoreTests {

    private func makeSut() -> CoachMarkDismissalStore {
        let suiteName = "com.bizarrecrm.test.coachmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return CoachMarkDismissalStore(defaults: defaults)
    }

    // MARK: Initial state

    @Test("isDismissed returns false for all screens by default")
    func allFalseByDefault() {
        let sut = makeSut()
        for screen in CoachMarkScreen.allCases {
            #expect(sut.isDismissed(screen) == false, "Expected false for \(screen.rawValue)")
        }
    }

    // MARK: dismiss(_:)

    @Test("dismiss marks specific screen as dismissed")
    func dismissesSpecificScreen() {
        let sut = makeSut()
        sut.dismiss(.dashboard)
        #expect(sut.isDismissed(.dashboard) == true)
    }

    @Test("dismiss does not affect other screens")
    func dismissDoesNotAffectOthers() {
        let sut = makeSut()
        sut.dismiss(.dashboard)
        // All other screens should still be undismissed.
        let others = CoachMarkScreen.allCases.filter { $0 != .dashboard }
        for screen in others {
            #expect(sut.isDismissed(screen) == false, "Expected false for \(screen.rawValue)")
        }
    }

    @Test("dismissing twice is idempotent")
    func dismissTwiceIsIdempotent() {
        let sut = makeSut()
        sut.dismiss(.tickets)
        sut.dismiss(.tickets)
        #expect(sut.isDismissed(.tickets) == true)
    }

    // MARK: resetAll()

    @Test("resetAll restores all screens to undismissed")
    func resetAllClearsAll() {
        let sut = makeSut()
        for screen in CoachMarkScreen.allCases {
            sut.dismiss(screen)
        }
        sut.resetAll()
        for screen in CoachMarkScreen.allCases {
            #expect(sut.isDismissed(screen) == false, "Expected false after reset for \(screen.rawValue)")
        }
    }

    // MARK: Persistence round-trip

    @Test("dismissed state persists across re-init")
    func persistenceRoundTrip() {
        let suiteName = "com.bizarrecrm.test.coachmark.rt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut1 = CoachMarkDismissalStore(defaults: defaults)
        sut1.dismiss(.customers)
        sut1.dismiss(.pos)

        let sut2 = CoachMarkDismissalStore(defaults: defaults)
        #expect(sut2.isDismissed(.customers) == true)
        #expect(sut2.isDismissed(.pos) == true)
        #expect(sut2.isDismissed(.dashboard) == false)
    }

    // MARK: All CoachMarkScreen cases compile and are unique

    @Test("all CoachMarkScreen rawValues are unique")
    func uniqueRawValues() {
        let values = CoachMarkScreen.allCases.map { $0.rawValue }
        let unique = Set(values)
        #expect(values.count == unique.count)
    }
}
