import Testing
import Foundation
@testable import DesignSystem

// §68 — StateRestorer tests

@Suite("StateRestorer")
struct StateRestorerTests {

    private func makeSut() -> StateRestorer {
        let suiteName = "com.bizarrecrm.test.staterestorer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return StateRestorer(defaults: defaults)
    }

    // MARK: Initial state

    @Test("lastTabIndex is nil on fresh install")
    func initialTabIndexIsNil() {
        let sut = makeSut()
        #expect(sut.lastTabIndex == nil)
    }

    @Test("lastRowID is nil on fresh install")
    func initialRowIDIsNil() {
        let sut = makeSut()
        #expect(sut.lastRowID == nil)
    }

    // MARK: Tab index

    @Test("stores and retrieves tab index 0")
    func storesTabIndex0() {
        let sut = makeSut()
        sut.lastTabIndex = 0
        #expect(sut.lastTabIndex == 0)
    }

    @Test("stores and retrieves tab index 4")
    func storesTabIndex4() {
        let sut = makeSut()
        sut.lastTabIndex = 4
        #expect(sut.lastTabIndex == 4)
    }

    @Test("setting lastTabIndex to nil clears value")
    func clearsTabIndex() {
        let sut = makeSut()
        sut.lastTabIndex = 2
        sut.lastTabIndex = nil
        #expect(sut.lastTabIndex == nil)
    }

    // MARK: Row ID

    @Test("stores and retrieves row ID")
    func storesRowID() {
        let sut = makeSut()
        let id = "abc-123"
        sut.lastRowID = id
        #expect(sut.lastRowID == id)
    }

    @Test("setting lastRowID to nil clears value")
    func clearsRowID() {
        let sut = makeSut()
        sut.lastRowID = "xyz"
        sut.lastRowID = nil
        #expect(sut.lastRowID == nil)
    }

    // MARK: Persistence round-trip

    @Test("values survive re-init with same defaults")
    func persistenceRoundTrip() {
        let suiteName = "com.bizarrecrm.test.staterestorer.rt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut1 = StateRestorer(defaults: defaults)
        sut1.lastTabIndex = 3
        sut1.lastRowID    = "ticket-42"

        let sut2 = StateRestorer(defaults: defaults)
        #expect(sut2.lastTabIndex == 3)
        #expect(sut2.lastRowID    == "ticket-42")
    }

    // MARK: clear()

    @Test("clear() removes both tab index and row ID")
    func clearRemovesAll() {
        let sut = makeSut()
        sut.lastTabIndex = 1
        sut.lastRowID    = "some-row"
        sut.clear()
        #expect(sut.lastTabIndex == nil)
        #expect(sut.lastRowID    == nil)
    }
}
