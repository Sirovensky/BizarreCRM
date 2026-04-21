import Testing
import Foundation
@testable import DesignSystem

// §66 — HapticCatalog enum tests (enum membership + CaseIterable coverage)

@Suite("HapticCatalog")
struct HapticCatalogTests {

    @Test("HapticEvent has 17 cases")
    func hapticEventCaseCount() {
        #expect(HapticEvent.allCases.count == 17)
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
}
