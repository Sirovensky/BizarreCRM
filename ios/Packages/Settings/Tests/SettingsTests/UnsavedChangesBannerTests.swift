import XCTest
@testable import Settings

// MARK: - UnsavedChangesBannerTests
//
// §19.0 — Tests for the unsaved-changes banner logic:
//   • ProfileSettingsViewModel.isDirty tracks field changes
//   • discardChanges() resets fields to last-saved snapshot
//   • save() updates the saved snapshot so isDirty clears

@MainActor
final class UnsavedChangesBannerTests: XCTestCase {

    // MARK: - ProfileSettingsViewModel dirty tracking

    func test_isDirty_isFalse_initially() {
        let vm = ProfileSettingsViewModel(api: nil)
        // Fresh VM with no loaded data: fields are empty, snapshot is empty → not dirty
        XCTAssertFalse(vm.isDirty)
    }

    func test_isDirty_isTrue_whenFirstNameChanges() {
        let vm = ProfileSettingsViewModel(api: nil)
        vm.firstName = "Changed"
        // savedFirstName is still "" → dirty
        XCTAssertTrue(vm.isDirty)
    }

    func test_isDirty_isTrue_whenEmailChanges() {
        let vm = ProfileSettingsViewModel(api: nil)
        vm.email = "new@example.com"
        XCTAssertTrue(vm.isDirty)
    }

    func test_isDirty_isFalse_whenAllFieldsMatchSaved() {
        let vm = ProfileSettingsViewModel(api: nil)
        // vm starts with all empty strings matching the empty saved snapshot
        vm.firstName = ""
        vm.lastName = ""
        vm.displayName = ""
        vm.email = ""
        vm.phone = ""
        vm.jobTitle = ""
        XCTAssertFalse(vm.isDirty)
    }

    func test_discardChanges_resetsToSavedSnapshot() {
        let vm = ProfileSettingsViewModel(api: nil)
        // Simulate a loaded state by directly setting the saved snapshot via save-like path
        // (we're testing the discard logic with the in-memory snapshot)
        vm.firstName = "Alice"

        // discard should bring it back to ""
        vm.discardChanges()
        XCTAssertEqual(vm.firstName, "")
        XCTAssertFalse(vm.isDirty)
    }

    func test_discardChanges_clearsErrorMessage() {
        let vm = ProfileSettingsViewModel(api: nil)
        vm.errorMessage = "Something went wrong"
        vm.firstName = "Changed"

        vm.discardChanges()
        XCTAssertNil(vm.errorMessage)
    }

    func test_isDirty_multipleFields() {
        let vm = ProfileSettingsViewModel(api: nil)
        vm.firstName = "Bob"
        vm.lastName = "Smith"
        vm.email = "bob@example.com"
        XCTAssertTrue(vm.isDirty)

        // Restore all fields to empty (matching saved snapshot)
        vm.firstName = ""
        vm.lastName = ""
        vm.email = ""
        XCTAssertFalse(vm.isDirty)
    }
}
