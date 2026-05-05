import XCTest
@testable import Communications
import Networking
import Core

// MARK: - SmsComposerViewModelTests
// TDD: written before SmsComposerViewModel was implemented.

@MainActor
final class SmsComposerViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(prefill: String = "", phoneNumber: String = "+15550001111") -> SmsComposerViewModel {
        SmsComposerViewModel(phoneNumber: phoneNumber, prefillBody: prefill)
    }

    // MARK: - Initial state

    func test_init_draftEmpty_byDefault() {
        let sut = makeSUT()
        XCTAssertTrue(sut.draft.isEmpty)
    }

    func test_init_prefill_setsInitialDraft() {
        let sut = makeSUT(prefill: "Hello {first_name}")
        XCTAssertEqual(sut.draft, "Hello {first_name}")
    }

    func test_init_charCountZero_whenDraftEmpty() {
        let sut = makeSUT()
        XCTAssertEqual(sut.charCount, 0)
    }

    // MARK: - Character counter

    func test_charCount_updatesWithDraft() {
        let sut = makeSUT()
        sut.draft = "Hello"
        XCTAssertEqual(sut.charCount, 5)
    }

    func test_smsSegmentCount_singleSegment_under160() {
        let sut = makeSUT()
        sut.draft = String(repeating: "a", count: 160)
        XCTAssertEqual(sut.smsSegmentCount, 1)
    }

    func test_smsSegmentCount_twoSegments_over160() {
        let sut = makeSUT()
        sut.draft = String(repeating: "a", count: 161)
        XCTAssertEqual(sut.smsSegmentCount, 2)
    }

    func test_smsSegmentCount_exactlyOneSegment_at160() {
        let sut = makeSUT()
        sut.draft = String(repeating: "b", count: 160)
        XCTAssertEqual(sut.smsSegmentCount, 1)
    }

    func test_smsSegmentCount_threeSegments_over320() {
        let sut = makeSUT()
        sut.draft = String(repeating: "c", count: 321)
        XCTAssertEqual(sut.smsSegmentCount, 3)
    }

    func test_smsSegmentCount_empty_isZero() {
        let sut = makeSUT()
        XCTAssertEqual(sut.smsSegmentCount, 0)
    }

    // MARK: - Insert at cursor

    func test_insertAtCursor_appendsToEndWhenNoCursorSet() {
        let sut = makeSUT()
        sut.draft = "Hello"
        sut.insertAtCursor("{first_name}")
        XCTAssertEqual(sut.draft, "Hello{first_name}")
    }

    func test_insertAtCursor_insertsAtMidpoint() {
        let sut = makeSUT()
        sut.draft = "Hi !"
        // Set cursor at index 3 (after "Hi ")
        sut.cursorOffset = 3
        sut.insertAtCursor("{first_name}")
        XCTAssertEqual(sut.draft, "Hi {first_name}!")
    }

    func test_insertAtCursor_atStart_prependsVar() {
        let sut = makeSUT()
        sut.draft = " world"
        sut.cursorOffset = 0
        sut.insertAtCursor("{first_name}")
        XCTAssertEqual(sut.draft, "{first_name} world")
    }

    func test_insertAtCursor_movesOffsetAfterInsertedToken() {
        let sut = makeSUT()
        sut.draft = "AB"
        sut.cursorOffset = 1
        sut.insertAtCursor("{x}")
        // cursor should advance past the inserted token
        XCTAssertEqual(sut.cursorOffset, 4) // 1 + len("{x}") == 4
    }

    // MARK: - Live preview

    func test_livePreview_substitutesSampleData() {
        let sut = makeSUT()
        sut.draft = "Hi {first_name}!"
        XCTAssertFalse(sut.livePreview.contains("{first_name}"))
        XCTAssertTrue(sut.livePreview.contains("Hi "))
    }

    func test_livePreview_emptyDraft_returnsEmpty() {
        let sut = makeSUT()
        XCTAssertTrue(sut.livePreview.isEmpty)
    }

    // MARK: - isValid

    func test_isValid_falseForEmptyDraft() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isValid)
    }

    func test_isValid_falseForWhitespaceOnly() {
        let sut = makeSUT()
        sut.draft = "   "
        XCTAssertFalse(sut.isValid)
    }

    func test_isValid_trueForNonEmptyDraft() {
        let sut = makeSUT()
        sut.draft = "Hello"
        XCTAssertTrue(sut.isValid)
    }

    // MARK: - Load template

    func test_loadTemplate_setsDraftToTemplateBody() {
        let sut = makeSUT()
        let template = MessageTemplate(id: 1, name: "T", body: "Hi {first_name}", channel: .sms, category: .reminder)
        sut.loadTemplate(template)
        XCTAssertEqual(sut.draft, "Hi {first_name}")
    }

    func test_loadTemplate_resetsCursorToEnd() {
        let sut = makeSUT()
        sut.draft = "Old content"
        sut.cursorOffset = 3
        let template = MessageTemplate(id: 2, name: "T2", body: "New", channel: .sms, category: .promo)
        sut.loadTemplate(template)
        XCTAssertEqual(sut.cursorOffset, sut.draft.count)
    }

    // MARK: - Known chip vars

    func test_knownVars_containsAllRequiredChips() {
        let required = ["{first_name}", "{ticket_no}", "{total}", "{due_date}", "{tech_name}", "{appointment_time}", "{shop_name}"]
        for v in required {
            XCTAssertTrue(SmsComposerViewModel.knownVars.contains(v), "Missing chip var: \(v)")
        }
    }
}
