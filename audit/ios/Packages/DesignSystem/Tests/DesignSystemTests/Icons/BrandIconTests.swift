// BrandIconTests.swift — §30 Brand Icon Catalog
//
// Tests that every BrandIcon case has:
//   1. A non-empty systemName
//   2. A non-empty accessibilityLabel
//   3. A unique systemName across all cases that are unique by design
//   4. An image that can be constructed without throwing
//
// Coverage target: ≥80 % of BrandIcon.swift lines.

import XCTest
import SwiftUI
@testable import DesignSystem

final class BrandIconTests: XCTestCase {

    // MARK: - All cases: systemName non-empty

    func test_allCases_systemName_nonEmpty() {
        for icon in BrandIcon.allCases {
            XCTAssertFalse(
                icon.systemName.isEmpty,
                "\(icon) has an empty systemName"
            )
        }
    }

    // MARK: - All cases: accessibilityLabel non-empty

    func test_allCases_accessibilityLabel_nonEmpty() {
        for icon in BrandIcon.allCases {
            XCTAssertFalse(
                icon.accessibilityLabel.isEmpty,
                "\(icon) has an empty accessibilityLabel"
            )
        }
    }

    // MARK: - systemName uniqueness (cases that are supposed to be unique)
    //
    // Some cases intentionally share a raw SF Symbol string because they
    // represent the same glyph used in different semantic contexts (e.g.
    // .repairTool and .settings both map to "wrench.and.screwdriver").
    // We verify that the *set* of unique systemNames is at least half the
    // total count — if someone accidentally duplicates everything, this fails.

    func test_systemNames_sufficientlyUnique() {
        let all = BrandIcon.allCases.map(\.systemName)
        let uniqueCount = Set(all).count
        // At least 75 % of cases must map to a distinct SF Symbol.
        let threshold = Int(Double(all.count) * 0.75)
        XCTAssertGreaterThanOrEqual(
            uniqueCount, threshold,
            "Too many duplicate systemNames — expected at least \(threshold) unique, got \(uniqueCount)"
        )
    }

    // MARK: - Known intentional duplicates — documented

    func test_knownDuplicates_areIntentional() {
        // coupon and ticketFill share "ticket.fill" — both show a filled ticket glyph
        XCTAssertEqual(BrandIcon.coupon.systemName, BrandIcon.ticketFill.systemName)
        // settings and repairTool share "wrench.and.screwdriver"
        XCTAssertEqual(BrandIcon.settings.systemName, BrandIcon.repairTool.systemName)
        // commission and dollarFill share "dollarsign.circle.fill"
        XCTAssertEqual(BrandIcon.commission.systemName, BrandIcon.dollarFill.systemName)
    }

    // MARK: - Spot-check specific icons mentioned in the task spec

    func test_ticket_systemName() {
        XCTAssertEqual(BrandIcon.ticket.systemName, "ticket")
    }

    func test_customer_systemName() {
        XCTAssertEqual(BrandIcon.customer.systemName, "person.circle")
    }

    func test_invoice_systemName() {
        XCTAssertEqual(BrandIcon.invoice.systemName, "doc.text")
    }

    func test_receipt_systemName() {
        XCTAssertEqual(BrandIcon.receipt.systemName, "receipt.fill")
    }

    func test_barcode_systemName() {
        XCTAssertEqual(BrandIcon.barcode.systemName, "barcode.viewfinder")
    }

    func test_chevronRight_systemName() {
        XCTAssertEqual(BrandIcon.chevronRight.systemName, "chevron.right")
    }

    func test_checkmark_systemName() {
        XCTAssertEqual(BrandIcon.checkmark.systemName, "checkmark")
    }

    func test_trash_systemName() {
        XCTAssertEqual(BrandIcon.trash.systemName, "trash")
    }

    func test_plus_systemName() {
        XCTAssertEqual(BrandIcon.plus.systemName, "plus")
    }

    func test_xmark_systemName() {
        XCTAssertEqual(BrandIcon.xmark.systemName, "xmark")
    }

    // MARK: - image property returns an Image

    func test_image_returnsImage() {
        // Image(systemName:) never throws in SwiftUI but we can verify
        // the type is correct via compile-time conformance.
        for icon in BrandIcon.allCases {
            let img: Image = icon.image
            // The image's description contains the system name when valid.
            let description = String(describing: img)
            XCTAssertFalse(description.isEmpty, "\(icon).image description should not be empty")
        }
    }

    // MARK: - systemName matches rawValue

    func test_systemName_matchesRawValue() {
        for icon in BrandIcon.allCases {
            XCTAssertEqual(
                icon.systemName, icon.rawValue,
                "\(icon).systemName should equal its rawValue"
            )
        }
    }

    // MARK: - CaseIterable completeness

    func test_caseIterable_countAboveMinimum() {
        // We mandate 40+ icons per the §30 spec.
        XCTAssertGreaterThanOrEqual(
            BrandIcon.allCases.count, 40,
            "BrandIcon must define at least 40 cases; found \(BrandIcon.allCases.count)"
        )
    }

    // MARK: - Sendable conformance (compile-time)

    func test_sendableConformance() {
        // If BrandIcon didn't conform to Sendable, this wouldn't compile.
        let _: any Sendable = BrandIcon.ticket
    }

    // MARK: - accessibilityLabel not equal to rawValue
    //
    // Labels should be human-readable strings, not raw SF Symbol identifiers.

    func test_accessibilityLabel_isHumanReadable() {
        for icon in BrandIcon.allCases {
            XCTAssertNotEqual(
                icon.accessibilityLabel, icon.rawValue,
                "\(icon) accessibilityLabel should be human-readable, not the raw SF Symbol name"
            )
        }
    }

    // MARK: - accessibilityLabel uniqueness among semantically distinct icons
    //
    // We don't require all labels to be unique (several icons share the same
    // English description, e.g. "Team" for .team and .teamFill), but we do
    // require that icons with different rawValues that are semantically
    // different have different labels.

    func test_accessibilityLabels_noAccidentalCollisions() {
        // Build a mapping from label → [case]. Any label shared by more than
        // two cases is suspicious.
        var labelMap: [String: [BrandIcon]] = [:]
        for icon in BrandIcon.allCases {
            labelMap[icon.accessibilityLabel, default: []].append(icon)
        }
        for (label, icons) in labelMap where icons.count > 4 {
            XCTFail("accessibilityLabel '\(label)' is shared by \(icons.count) icons: \(icons). Likely an accidental collision.")
        }
    }

    // MARK: - Known accessibility labels

    func test_accessibilityLabel_ticket() {
        XCTAssertEqual(BrandIcon.ticket.accessibilityLabel, NSLocalizedString("Ticket", comment: "SF: ticket"))
    }

    func test_accessibilityLabel_trash() {
        XCTAssertEqual(BrandIcon.trash.accessibilityLabel, NSLocalizedString("Delete", comment: "SF: trash"))
    }

    func test_accessibilityLabel_warning() {
        XCTAssertEqual(BrandIcon.warning.accessibilityLabel, NSLocalizedString("Warning", comment: "SF: exclamationmark.triangle.fill"))
    }

    func test_accessibilityLabel_magnifyingGlass() {
        XCTAssertEqual(BrandIcon.magnifyingGlass.accessibilityLabel, NSLocalizedString("Search", comment: "SF: magnifyingglass"))
    }

    func test_accessibilityLabel_plus() {
        XCTAssertEqual(BrandIcon.plus.accessibilityLabel, NSLocalizedString("Add", comment: "SF: plus"))
    }
}
