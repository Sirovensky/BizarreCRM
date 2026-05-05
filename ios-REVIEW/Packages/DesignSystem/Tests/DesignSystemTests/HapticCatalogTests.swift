import Testing
import Foundation
@testable import DesignSystem

// §66 — HapticCatalog enum tests (enum membership + CaseIterable coverage)

@Suite("HapticCatalog")
struct HapticCatalogTests {

    @Test("HapticEvent has 21 cases")
    func hapticEventCaseCount() {
        #expect(HapticEvent.allCases.count == 21)
    }

    @Test("HapticEvent rawValues are unique")
    func hapticEventRawValuesUnique() {
        let values = HapticEvent.allCases.map { $0.rawValue }
        #expect(Set(values).count == values.count)
    }

    @Test("HapticEvent conforms to Sendable via enum")
    func hapticEventSendable() {
        // Compile-time proof: Sendable enum can be captured in @Sendable closure.
        let event: HapticEvent = .saleComplete
        let _: @Sendable () -> HapticEvent = { event }
        #expect(true) // If this compiles, Sendable conformance is satisfied.
    }

    @Test("HapticEvent has saleComplete case")
    func hasSaleComplete() {
        #expect(HapticEvent.allCases.contains(.saleComplete))
    }

    @Test("HapticEvent has clockIn and clockOut")
    func hasClockInOut() {
        #expect(HapticEvent.allCases.contains(.clockIn))
        #expect(HapticEvent.allCases.contains(.clockOut))
    }

    @Test("HapticEvent has cardDeclined")
    func hasCardDeclined() {
        #expect(HapticEvent.allCases.contains(.cardDeclined))
    }

    @Test("HapticEvent has signatureCommit")
    func hasSignatureCommit() {
        #expect(HapticEvent.allCases.contains(.signatureCommit))
    }

    @Test("HapticEvent rawValue matches case name")
    func rawValueMatchesCaseName() {
        #expect(HapticEvent.saleComplete.rawValue == "saleComplete")
        #expect(HapticEvent.drawerKick.rawValue   == "drawerKick")
        #expect(HapticEvent.scanSuccess.rawValue  == "scanSuccess")
    }

    // §30 — new semantic event membership
    @Test("HapticEvent has buttonTap")
    func hasButtonTap() {
        #expect(HapticEvent.allCases.contains(.buttonTap))
    }

    @Test("HapticEvent has sheetPresented")
    func hasSheetPresented() {
        #expect(HapticEvent.allCases.contains(.sheetPresented))
    }

    @Test("HapticEvent has listItemAppear")
    func hasListItemAppear() {
        #expect(HapticEvent.allCases.contains(.listItemAppear))
    }

    @Test("HapticEvent has cardHoverActivate")
    func hasCardHoverActivate() {
        #expect(HapticEvent.allCases.contains(.cardHoverActivate))
    }

    @Test("§30 events have unique rawValues")
    func newEventsRawValuesUnique() {
        let newCases: [HapticEvent] = [.buttonTap, .sheetPresented, .listItemAppear, .cardHoverActivate]
        let values = newCases.map { $0.rawValue }
        #expect(Set(values).count == values.count)
    }
}
