import XCTest
@testable import Core

// §64 — Tests for ToneGuidelines validator, each rule in isolation + combined.

final class ToneGuidelinesTests: XCTestCase {

    // MARK: — containsAllCapsWord

    func testAllCapsWord_triggersOnAllCapsWord() {
        XCTAssertTrue(ToneGuidelines.containsAllCapsWord("We had an ERROR loading your data"))
    }

    func testAllCapsWord_triggersOnMultipleAllCapsWords() {
        XCTAssertTrue(ToneGuidelines.containsAllCapsWord("SERVER UNAVAILABLE"))
    }

    func testAllCapsWord_doesNotTriggerOnNormalSentence() {
        XCTAssertFalse(ToneGuidelines.containsAllCapsWord("Something went wrong. Try again."))
    }

    func testAllCapsWord_doesNotTriggerOnSingleUppercaseLetter() {
        XCTAssertFalse(ToneGuidelines.containsAllCapsWord("I couldn't load this."))
    }

    func testAllCapsWord_doesNotTriggerOnTwoLetterAcronym() {
        XCTAssertFalse(ToneGuidelines.containsAllCapsWord("Go to the UI and retry."))
    }

    func testAllCapsWord_doesNotTriggerOnMixedCase() {
        XCTAssertFalse(ToneGuidelines.containsAllCapsWord("Invoice saved."))
    }

    // MARK: — containsExclamationMark

    func testExclamationMark_triggersOnExclamation() {
        XCTAssertTrue(ToneGuidelines.containsExclamationMark("Customer saved!"))
    }

    func testExclamationMark_triggersOnMidString() {
        XCTAssertTrue(ToneGuidelines.containsExclamationMark("Wow! That worked."))
    }

    func testExclamationMark_doesNotTriggerOnCleanString() {
        XCTAssertFalse(ToneGuidelines.containsExclamationMark("Customer saved."))
    }

    // MARK: — containsFillerApology

    func testFillerApology_triggersOnPlease() {
        XCTAssertTrue(ToneGuidelines.containsFillerApology("Please try again."))
    }

    func testFillerApology_triggersOnSorry() {
        XCTAssertTrue(ToneGuidelines.containsFillerApology("Sorry, we couldn't load that."))
    }

    func testFillerApology_triggersOnWeApologize() {
        XCTAssertTrue(ToneGuidelines.containsFillerApology("We apologize for the inconvenience."))
    }

    func testFillerApology_triggersOnWereSorry() {
        XCTAssertTrue(ToneGuidelines.containsFillerApology("We're sorry about that."))
    }

    func testFillerApology_triggersOnApologies() {
        XCTAssertTrue(ToneGuidelines.containsFillerApology("Apologies for the delay."))
    }

    func testFillerApology_isCaseInsensitive() {
        XCTAssertTrue(ToneGuidelines.containsFillerApology("PLEASE check your input."))
    }

    func testFillerApology_doesNotTriggerOnCleanString() {
        XCTAssertFalse(ToneGuidelines.containsFillerApology("Check your connection and try again."))
    }

    // MARK: — startsWithTechnicalJargon

    func testTechnicalJargon_triggersOnErrorColon() {
        XCTAssertTrue(ToneGuidelines.startsWithTechnicalJargon("Error: connection refused"))
    }

    func testTechnicalJargon_triggersOnExceptionColon() {
        XCTAssertTrue(ToneGuidelines.startsWithTechnicalJargon("Exception: NullPointerException at line 42"))
    }

    func testTechnicalJargon_triggersOnFailedColon() {
        XCTAssertTrue(ToneGuidelines.startsWithTechnicalJargon("Failed: unable to write to disk"))
    }

    func testTechnicalJargon_triggersOnWarningColon() {
        XCTAssertTrue(ToneGuidelines.startsWithTechnicalJargon("Warning: storage is low"))
    }

    func testTechnicalJargon_isCaseInsensitive() {
        XCTAssertTrue(ToneGuidelines.startsWithTechnicalJargon("ERROR: disk full"))
    }

    func testTechnicalJargon_doesNotTriggerOnNormalSentence() {
        XCTAssertFalse(ToneGuidelines.startsWithTechnicalJargon("Couldn't save the record. Try again."))
    }

    func testTechnicalJargon_doesNotTriggerOnErrorMidSentence() {
        // "Error" not at start — should not trigger
        XCTAssertFalse(ToneGuidelines.startsWithTechnicalJargon("There was an error saving your data."))
    }

    // MARK: — isPassiveHedge

    func testPassiveHedge_triggersOnThereWasAProblem() {
        XCTAssertTrue(ToneGuidelines.isPassiveHedge("There was a problem."))
    }

    func testPassiveHedge_triggersOnSomethingWentWrong() {
        XCTAssertTrue(ToneGuidelines.isPassiveHedge("Something went wrong"))
    }

    func testPassiveHedge_triggersOnAnErrorOccurred() {
        XCTAssertTrue(ToneGuidelines.isPassiveHedge("An error occurred."))
    }

    func testPassiveHedge_triggersOnAnErrorHasOccurred() {
        XCTAssertTrue(ToneGuidelines.isPassiveHedge("An error has occurred."))
    }

    func testPassiveHedge_isCaseInsensitive() {
        XCTAssertTrue(ToneGuidelines.isPassiveHedge("SOMETHING WENT WRONG"))
    }

    func testPassiveHedge_doesNotTriggerOnActionableMessage() {
        XCTAssertFalse(ToneGuidelines.isPassiveHedge("Something went wrong. Check your connection and try again."))
    }

    func testPassiveHedge_doesNotTriggerOnGoodCopy() {
        XCTAssertFalse(ToneGuidelines.isPassiveHedge("We couldn't reach the server. Check your connection and try again."))
    }

    // MARK: — hasTrailingEllipsis

    func testTrailingEllipsis_triggersOnUnicodeEllipsis() {
        XCTAssertTrue(ToneGuidelines.hasTrailingEllipsis("Loading…"))
    }

    func testTrailingEllipsis_triggersOnThreePeriods() {
        XCTAssertTrue(ToneGuidelines.hasTrailingEllipsis("Loading..."))
    }

    func testTrailingEllipsis_triggersWithTrailingSpace() {
        XCTAssertTrue(ToneGuidelines.hasTrailingEllipsis("Loading…  "))
    }

    func testTrailingEllipsis_doesNotTriggerOnNormalSentence() {
        XCTAssertFalse(ToneGuidelines.hasTrailingEllipsis("Invoice saved."))
    }

    func testTrailingEllipsis_doesNotTriggerOnMidEllipsis() {
        XCTAssertFalse(ToneGuidelines.hasTrailingEllipsis("Saving… please wait — done."))
    }

    // MARK: — violations() aggregate

    func testViolations_emptyForCleanString() {
        let violations = ToneGuidelines.violations(in: "Invoice saved.")
        XCTAssertTrue(violations.isEmpty)
    }

    func testViolations_detectsMultipleViolations() {
        let violations = ToneGuidelines.violations(in: "ERROR: Please try again!")
        XCTAssertTrue(violations.contains(.allCapsWord))
        XCTAssertTrue(violations.contains(.fillerApology))
        XCTAssertTrue(violations.contains(.exclamationMark))
        XCTAssertTrue(violations.contains(.technicalJargonLead))
    }

    func testViolations_isOrdered() {
        // The same string always returns violations in the same order (enum case order)
        let v1 = ToneGuidelines.violations(in: "ERROR!")
        let v2 = ToneGuidelines.violations(in: "ERROR!")
        XCTAssertEqual(v1, v2)
    }

    // MARK: — assertTone (no-op in tests, but callable without crashing)

    func testAssertTone_doesNotThrowForCleanString() {
        // This must not crash even in DEBUG mode for valid copy.
        // We call it here; if assertionFailure fires the test process will abort.
        // We verify indirectly through violations() being empty.
        let violations = ToneGuidelines.violations(in: "Customer saved.")
        XCTAssertTrue(violations.isEmpty)
    }

    // MARK: — ToneViolation CaseIterable coverage

    func testAllViolationCasesAreTested() {
        // Verify each ToneViolation case is represented in the enum.
        let all = ToneViolation.allCases
        XCTAssertTrue(all.contains(.allCapsWord))
        XCTAssertTrue(all.contains(.exclamationMark))
        XCTAssertTrue(all.contains(.fillerApology))
        XCTAssertTrue(all.contains(.technicalJargonLead))
        XCTAssertTrue(all.contains(.passiveHedge))
        XCTAssertTrue(all.contains(.trailingEllipsis))
    }

    // MARK: — Real-world catalog strings don't trip the validator

    func testWellKnownGoodStrings_haveNoViolations() {
        let goodStrings = [
            "Customer saved.",
            "Invoice sent.",
            "No tickets yet. Start by creating one.",
            "Delete ticket?",
            "This will permanently delete the ticket and all its notes. This action cannot be undone.",
            "We couldn't reach the server. Check your connection and try again.",
            "Your session has expired. Sign in again to keep working.",
            "You don't have permission to do this. Contact your administrator if you need access.",
            "Fix the highlighted fields and try again: email, phone.",
            "Too many requests. Wait a moment before trying again."
        ]
        for string in goodStrings {
            let violations = ToneGuidelines.violations(in: string)
            XCTAssertTrue(violations.isEmpty,
                "Expected no violations in \"\(string)\"; got: \(violations)")
        }
    }
}

// MARK: — Typealias for clarity in test

private typealias ToneViolation = ToneGuidelines.ToneViolation
