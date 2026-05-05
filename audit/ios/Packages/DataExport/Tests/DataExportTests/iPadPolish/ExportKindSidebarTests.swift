import Testing
import Foundation
@testable import DataExport

// MARK: - ExportKindTests

@Suite("ExportKind — sidebar data model")
struct ExportKindTests {

    // MARK: - CaseIterable

    @Test("ExportKind has exactly 4 cases")
    func exportKindCaseCount() {
        #expect(ExportKind.allCases.count == 4)
    }

    @Test("ExportKind.allCases contains all expected cases")
    func exportKindAllCases() {
        let rawValues = ExportKind.allCases.map(\.rawValue)
        #expect(rawValues.contains("on_demand"))
        #expect(rawValues.contains("scheduled"))
        #expect(rawValues.contains("gdpr"))
        #expect(rawValues.contains("settings"))
    }

    // MARK: - Identifiable

    @Test("ExportKind.id equals rawValue")
    func exportKindIdEqualsRawValue() {
        for kind in ExportKind.allCases {
            #expect(kind.id == kind.rawValue)
        }
    }

    // MARK: - displayName

    @Test("ExportKind.onDemand displayName is 'On-Demand'")
    func onDemandDisplayName() {
        #expect(ExportKind.onDemand.displayName == "On-Demand")
    }

    @Test("ExportKind.scheduled displayName is 'Scheduled'")
    func scheduledDisplayName() {
        #expect(ExportKind.scheduled.displayName == "Scheduled")
    }

    @Test("ExportKind.gdpr displayName is 'GDPR'")
    func gdprDisplayName() {
        #expect(ExportKind.gdpr.displayName == "GDPR")
    }

    @Test("ExportKind.settings displayName is 'Settings'")
    func settingsDisplayName() {
        #expect(ExportKind.settings.displayName == "Settings")
    }

    // MARK: - systemImage

    @Test("Every ExportKind has a non-empty systemImage")
    func allKindsHaveSystemImage() {
        for kind in ExportKind.allCases {
            #expect(!kind.systemImage.isEmpty, "ExportKind.\(kind) has empty systemImage")
        }
    }

    @Test("ExportKind.onDemand systemImage is 'arrow.down.circle.fill'")
    func onDemandSystemImage() {
        #expect(ExportKind.onDemand.systemImage == "arrow.down.circle.fill")
    }

    @Test("ExportKind.scheduled systemImage is 'calendar.badge.clock'")
    func scheduledSystemImage() {
        #expect(ExportKind.scheduled.systemImage == "calendar.badge.clock")
    }

    @Test("ExportKind.gdpr systemImage is 'person.badge.shield.checkmark.fill'")
    func gdprSystemImage() {
        #expect(ExportKind.gdpr.systemImage == "person.badge.shield.checkmark.fill")
    }

    @Test("ExportKind.settings systemImage is 'gearshape.2.fill'")
    func settingsSystemImage() {
        #expect(ExportKind.settings.systemImage == "gearshape.2.fill")
    }

    // MARK: - accessibilityHint

    @Test("Every ExportKind has a non-empty accessibilityHint")
    func allKindsHaveAccessibilityHint() {
        for kind in ExportKind.allCases {
            #expect(!kind.accessibilityHint.isEmpty, "ExportKind.\(kind) has empty accessibilityHint")
        }
    }

    @Test("ExportKind.onDemand accessibilityHint mentions on-demand exports")
    func onDemandHint() {
        let hint = ExportKind.onDemand.accessibilityHint.lowercased()
        #expect(hint.contains("on-demand") || hint.contains("export"))
    }

    @Test("ExportKind.gdpr accessibilityHint mentions customer or personal data")
    func gdprHint() {
        let hint = ExportKind.gdpr.accessibilityHint.lowercased()
        #expect(hint.contains("customer") || hint.contains("personal") || hint.contains("data"))
    }

    // MARK: - Sendable / Hashable

    @Test("ExportKind values can be used in a Set (Hashable via RawRepresentable)")
    func exportKindHashable() {
        let set: Set<ExportKind> = [.onDemand, .scheduled, .onDemand]
        #expect(set.count == 2)
    }

    @Test("ExportKind equality works correctly")
    func exportKindEquality() {
        #expect(ExportKind.onDemand == ExportKind.onDemand)
        #expect(ExportKind.gdpr != ExportKind.settings)
    }

    // MARK: - RawRepresentable round-trip

    @Test("ExportKind initialises from valid rawValue")
    func exportKindFromRawValue() {
        #expect(ExportKind(rawValue: "scheduled") == .scheduled)
        #expect(ExportKind(rawValue: "gdpr") == .gdpr)
    }

    @Test("ExportKind returns nil for unknown rawValue")
    func exportKindUnknownRawValue() {
        #expect(ExportKind(rawValue: "unknown_kind") == nil)
    }
}
