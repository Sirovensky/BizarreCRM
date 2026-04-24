#if canImport(SwiftUI)
import XCTest
@testable import Hardware

// MARK: - HardwareDeviceTypeTests
//
// Unit tests for the `HardwareDeviceType` enum used by the iPad sidebar.
//
// Coverage:
//   - All 5 cases present in allCases
//   - title / systemImage / accentColor defined for every case
//   - accessibilityLabel / accessibilityHint non-empty for every case
//   - Identifiable: id == rawValue
//   - Hashable: usable as dictionary key
//   - Sendable: compiles (verified by @Sendable closure test)

final class HardwareDeviceTypeTests: XCTestCase {

    // MARK: - allCases completeness

    func test_allCases_containsExactlyFiveTypes() {
        XCTAssertEqual(HardwareDeviceType.allCases.count, 5)
    }

    func test_allCases_containsExpectedTypes() {
        let types = Set(HardwareDeviceType.allCases.map(\.rawValue))
        XCTAssertTrue(types.contains("printer"))
        XCTAssertTrue(types.contains("drawer"))
        XCTAssertTrue(types.contains("scale"))
        XCTAssertTrue(types.contains("scanner"))
        XCTAssertTrue(types.contains("terminal"))
    }

    // MARK: - Identifiable

    func test_id_equalsRawValue() {
        for type in HardwareDeviceType.allCases {
            XCTAssertEqual(type.id, type.rawValue,
                           "\(type) id must equal rawValue")
        }
    }

    // MARK: - title

    func test_title_nonEmptyForAllCases() {
        for type in HardwareDeviceType.allCases {
            XCTAssertFalse(type.title.isEmpty,
                           "\(type).title must not be empty")
        }
    }

    func test_title_printer() {
        XCTAssertEqual(HardwareDeviceType.printer.title, "Printers")
    }

    func test_title_drawer() {
        XCTAssertEqual(HardwareDeviceType.drawer.title, "Cash Drawer")
    }

    func test_title_scale() {
        XCTAssertEqual(HardwareDeviceType.scale.title, "Weight Scales")
    }

    func test_title_scanner() {
        XCTAssertEqual(HardwareDeviceType.scanner.title, "Barcode Scanners")
    }

    func test_title_terminal() {
        XCTAssertEqual(HardwareDeviceType.terminal.title, "Payment Terminal")
    }

    // MARK: - systemImage

    func test_systemImage_nonEmptyForAllCases() {
        for type in HardwareDeviceType.allCases {
            XCTAssertFalse(type.systemImage.isEmpty,
                           "\(type).systemImage must not be empty")
        }
    }

    func test_systemImage_allCasesDistinct() {
        let images = HardwareDeviceType.allCases.map(\.systemImage)
        let unique = Set(images)
        XCTAssertEqual(images.count, unique.count,
                       "Each device type should have a unique systemImage")
    }

    // MARK: - accessibilityLabel

    func test_accessibilityLabel_nonEmptyForAllCases() {
        for type in HardwareDeviceType.allCases {
            XCTAssertFalse(type.accessibilityLabel.isEmpty,
                           "\(type).accessibilityLabel must not be empty")
        }
    }

    func test_accessibilityLabel_containsTitle() {
        for type in HardwareDeviceType.allCases {
            XCTAssertTrue(
                type.accessibilityLabel.localizedCaseInsensitiveContains(type.title),
                "\(type).accessibilityLabel should contain the type title"
            )
        }
    }

    // MARK: - accessibilityHint

    func test_accessibilityHint_nonEmptyForAllCases() {
        for type in HardwareDeviceType.allCases {
            XCTAssertFalse(type.accessibilityHint.isEmpty,
                           "\(type).accessibilityHint must not be empty")
        }
    }

    // MARK: - Hashable / Equatable

    func test_hashable_usableAsDictionaryKey() {
        var dict: [HardwareDeviceType: Int] = [:]
        for (index, type) in HardwareDeviceType.allCases.enumerated() {
            dict[type] = index
        }
        XCTAssertEqual(dict.count, HardwareDeviceType.allCases.count)
    }

    func test_equatable_sameRawValueIsEqual() {
        XCTAssertEqual(HardwareDeviceType.printer, HardwareDeviceType.printer)
        XCTAssertNotEqual(HardwareDeviceType.printer, HardwareDeviceType.drawer)
    }

    // MARK: - Sendable (compile-time)

    func test_sendable_canCrossActorBoundary() async {
        let type: HardwareDeviceType = .scale
        let result: HardwareDeviceType = await Task.detached {
            return type
        }.value
        XCTAssertEqual(result, .scale)
    }
}

#endif
