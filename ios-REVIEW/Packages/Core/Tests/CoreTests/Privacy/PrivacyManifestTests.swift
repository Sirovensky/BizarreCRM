import XCTest
@testable import Core

// §28 Security & Privacy helpers — PrivacyManifest tests

final class PrivacyManifestTests: XCTestCase {

    // MARK: - bizarreCRM manifest completeness

    func test_bizarreCRM_coversAllRequiredAPITypes() {
        XCTAssertTrue(
            PrivacyManifest.bizarreCRM.coversAllRequiredTypes,
            "The BizarreCRM manifest must declare all required NSPrivacyAccessedAPITypes"
        )
    }

    func test_bizarreCRM_declaresUserDefaults() {
        let entry = PrivacyManifest.bizarreCRM.entry(for: .userDefaults)
        XCTAssertNotNil(entry, "UserDefaults entry must be declared")
        XCTAssertFalse(entry!.reasons.isEmpty)
    }

    func test_bizarreCRM_declaresFileTimestamp() {
        let entry = PrivacyManifest.bizarreCRM.entry(for: .fileTimestamp)
        XCTAssertNotNil(entry, "FileTimestamp entry must be declared")
        XCTAssertFalse(entry!.reasons.isEmpty)
    }

    func test_bizarreCRM_declaresSystemBootTime() {
        let entry = PrivacyManifest.bizarreCRM.entry(for: .systemBootTime)
        XCTAssertNotNil(entry, "SystemBootTime entry must be declared")
        XCTAssertFalse(entry!.reasons.isEmpty)
    }

    func test_bizarreCRM_declaresDiskSpace() {
        let entry = PrivacyManifest.bizarreCRM.entry(for: .diskSpace)
        XCTAssertNotNil(entry, "DiskSpace entry must be declared")
        XCTAssertFalse(entry!.reasons.isEmpty)
    }

    // MARK: - PrivacyAPIType raw values match Apple's strings

    func test_apiType_rawValues() {
        XCTAssertEqual(PrivacyAPIType.userDefaults.rawValue,
                       "NSPrivacyAccessedAPICategoryUserDefaults")
        XCTAssertEqual(PrivacyAPIType.fileTimestamp.rawValue,
                       "NSPrivacyAccessedAPICategoryFileTimestamp")
        XCTAssertEqual(PrivacyAPIType.systemBootTime.rawValue,
                       "NSPrivacyAccessedAPICategorySystemBootTime")
        XCTAssertEqual(PrivacyAPIType.diskSpace.rawValue,
                       "NSPrivacyAccessedAPICategoryDiskSpace")
    }

    // MARK: - PrivacyAPIEntry initialisation guard

    func test_entry_withReasons_doesNotPreconditionFail() {
        // This just verifies the happy path compiles and runs.
        let entry = PrivacyAPIEntry(apiType: .userDefaults, reasons: [.userDefaultsCA92])
        XCTAssertEqual(entry.apiType, .userDefaults)
        XCTAssertEqual(entry.reasons.count, 1)
    }

    // MARK: - Custom manifest lookup

    func test_entry_lookup_returnsNilForUndeclaredType() {
        let partial = PrivacyManifest(accessedAPITypes: [
            PrivacyAPIEntry(apiType: .userDefaults, reasons: [.userDefaultsCA92])
        ])
        XCTAssertNil(partial.entry(for: .diskSpace))
    }

    func test_coversAllRequiredTypes_false_whenMissingEntries() {
        let partial = PrivacyManifest(accessedAPITypes: [
            PrivacyAPIEntry(apiType: .userDefaults, reasons: [.userDefaultsCA92]),
            PrivacyAPIEntry(apiType: .fileTimestamp, reasons: [.fileTimestampC617])
            // missing systemBootTime and diskSpace
        ])
        XCTAssertFalse(partial.coversAllRequiredTypes)
    }

    // MARK: - Reason code round-trips

    func test_reasonCode_rawValue_preservedRoundTrip() {
        let code = PrivacyAPIReasonCode(rawValue: "CA92.1")
        XCTAssertEqual(code.rawValue, "CA92.1")
        XCTAssertEqual(code, .userDefaultsCA92)
    }

    // MARK: - CaseIterable coverage

    func test_allAPITypesCases_count() {
        // Verifies we haven't silently added a case without updating this test.
        XCTAssertEqual(PrivacyAPIType.allCases.count, 4,
                       "Update this test if a new PrivacyAPIType case is added")
    }
}
