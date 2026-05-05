import Testing
import SwiftUI
@testable import DesignSystem

// §30 — SemanticBadge tests

@Suite("SemanticBadge")
struct SemanticBadgeTests {

    // MARK: - SemanticBadgeSeverity enum

    @Test("SemanticBadgeSeverity has 4 cases")
    func severityCaseCount() {
        #expect(SemanticBadgeSeverity.allCases.count == 4)
    }

    @Test("SemanticBadgeSeverity allCases contains success, warning, danger, info")
    func severityAllCases() {
        let cases = SemanticBadgeSeverity.allCases
        #expect(cases.contains(.success))
        #expect(cases.contains(.warning))
        #expect(cases.contains(.danger))
        #expect(cases.contains(.info))
    }

    @Test("SemanticBadgeSeverity accessibilityHint strings are non-empty")
    func accessibilityHints() {
        for severity in SemanticBadgeSeverity.allCases {
            #expect(!severity.accessibilityHint.isEmpty)
        }
    }

    @Test("SemanticBadgeSeverity accessibilityHints are unique")
    func accessibilityHintsUnique() {
        let hints = SemanticBadgeSeverity.allCases.map { $0.accessibilityHint }
        #expect(Set(hints).count == hints.count)
    }

    @Test("SemanticBadgeSeverity foregroundColor is black for all (contrast on vivid bg)")
    func foregroundColorIsBlack() {
        // All vivid semantic backgrounds → black text meets 4.5:1 per §a11y.
        for severity in SemanticBadgeSeverity.allCases {
            #expect(severity.foregroundColor == .black)
        }
    }

    // MARK: - SemanticBadge view

    @Test("SemanticBadge initialises with success")
    func badgeSuccess() {
        let badge = SemanticBadge("Paid", severity: .success)
        let _: SemanticBadge = badge
        #expect(true)
    }

    @Test("SemanticBadge initialises with warning")
    func badgeWarning() {
        let badge = SemanticBadge("Pending", severity: .warning)
        let _: SemanticBadge = badge
        #expect(true)
    }

    @Test("SemanticBadge initialises with danger")
    func badgeDanger() {
        let badge = SemanticBadge("Overdue", severity: .danger)
        let _: SemanticBadge = badge
        #expect(true)
    }

    @Test("SemanticBadge initialises with info")
    func badgeInfo() {
        let badge = SemanticBadge("Draft", severity: .info)
        let _: SemanticBadge = badge
        #expect(true)
    }

    @Test("SemanticBadge conforms to View")
    func conformsToView() {
        let badge = SemanticBadge("OK", severity: .success)
        let _: any View = badge
        #expect(true)
    }
}
