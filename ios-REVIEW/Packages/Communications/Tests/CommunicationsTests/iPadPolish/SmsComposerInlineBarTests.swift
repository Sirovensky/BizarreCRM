import XCTest
@testable import Communications
@testable import Networking

// MARK: - SmsComposerInlineBarTests
//
// Tests for the inline bar's view-model-level logic.
// SmsComposerViewModel (reused by SmsComposerInlineBar) owns all state;
// we test its behaviour as the inline bar would drive it.

final class SmsComposerInlineBarTests: XCTestCase {

    // MARK: - Draft state

    @MainActor
    func test_freshViewModel_draftIsEmpty() {
        let vm = SmsComposerViewModel(phoneNumber: "+10005550002")
        XCTAssertTrue(vm.draft.isEmpty)
    }

    @MainActor
    func test_isValid_falseWhenDraftIsEmpty() {
        let vm = SmsComposerViewModel(phoneNumber: "+10005550002")
        XCTAssertFalse(vm.isValid)
    }

    @MainActor
    func test_isValid_trueWhenDraftHasContent() {
        let vm = SmsComposerViewModel(phoneNumber: "+10005550002", prefillBody: "Hello")
        XCTAssertTrue(vm.isValid)
    }

    @MainActor
    func test_isValid_falseWhenDraftIsWhitespaceOnly() {
        let vm = SmsComposerViewModel(phoneNumber: "+10005550002", prefillBody: "   ")
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - charCount

    @MainActor
    func test_charCount_matchesDraftLength() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: "Hi there")
        XCTAssertEqual(vm.charCount, "Hi there".count)
    }

    // MARK: - smsSegmentCount

    @MainActor
    func test_segmentCount_zeroForEmptyDraft() {
        let vm = SmsComposerViewModel(phoneNumber: "+1")
        XCTAssertEqual(vm.smsSegmentCount, 0)
    }

    @MainActor
    func test_segmentCount_oneForShortDraft() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: "Short")
        XCTAssertEqual(vm.smsSegmentCount, 1)
    }

    @MainActor
    func test_segmentCount_twoFor161CharDraft() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: String(repeating: "x", count: 161))
        XCTAssertEqual(vm.smsSegmentCount, 2)
    }

    @MainActor
    func test_segmentCount_exactlyOneFor160Chars() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: String(repeating: "x", count: 160))
        XCTAssertEqual(vm.smsSegmentCount, 1)
    }

    // MARK: - insertAtCursor

    @MainActor
    func test_insertAtCursor_appendsWhenCursorIsNil() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: "Hello ")
        vm.cursorOffset = nil
        vm.insertAtCursor("{first_name}")
        XCTAssertEqual(vm.draft, "Hello {first_name}")
    }

    @MainActor
    func test_insertAtCursor_insertsAtPosition() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: "Hello World")
        vm.cursorOffset = 5     // after "Hello"
        vm.insertAtCursor(",")
        XCTAssertEqual(vm.draft, "Hello, World")
    }

    @MainActor
    func test_insertAtCursor_advancesCursorAfterInsertion() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: "Hi")
        vm.cursorOffset = 2
        vm.insertAtCursor("{name}")
        XCTAssertEqual(vm.cursorOffset, 2 + "{name}".count)
    }

    // MARK: - loadTemplate

    @MainActor
    func test_loadTemplate_replacesDraft() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: "Old text")
        let tmpl = MessageTemplate(
            id: 1,
            name: "Test",
            body: "New body {first_name}",
            channel: .sms,
            category: .reminder,
            createdAt: nil
        )
        vm.loadTemplate(tmpl)
        XCTAssertEqual(vm.draft, "New body {first_name}")
    }

    @MainActor
    func test_loadTemplate_setsCursorToEnd() {
        let vm = SmsComposerViewModel(phoneNumber: "+1")
        let body = "Template content"
        let tmpl = MessageTemplate(
            id: 1,
            name: "T",
            body: body,
            channel: .sms,
            category: .reminder,
            createdAt: nil
        )
        vm.loadTemplate(tmpl)
        XCTAssertEqual(vm.cursorOffset, body.count)
    }

    // MARK: - canSend guard (via isValid + phone)

    @MainActor
    func test_isValid_falseAfterDraftCleared() {
        let vm = SmsComposerViewModel(phoneNumber: "+1", prefillBody: "Ready")
        vm.draft = ""
        XCTAssertFalse(vm.isValid)
    }

    // MARK: - knownVars

    func test_knownVars_notEmpty() {
        XCTAssertFalse(SmsComposerViewModel.knownVars.isEmpty)
    }

    func test_knownVars_containsFirstName() {
        XCTAssertTrue(SmsComposerViewModel.knownVars.contains("{first_name}"))
    }

    func test_knownVars_areUniqueStrings() {
        let vars = SmsComposerViewModel.knownVars
        XCTAssertEqual(Set(vars).count, vars.count)
    }
}
