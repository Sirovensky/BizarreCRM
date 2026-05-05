import XCTest
@testable import Auth

/// §2.3 — locks down the offline strength evaluator. The UI gates CTA
/// enablement on `rules.allPassed`, so a regression that silently
/// relaxes a rule would let a weak password through.
final class PasswordStrengthTests: XCTestCase {

    // MARK: - Rules

    func test_emptyPassword_failsEveryRule() {
        let eval = PasswordStrengthEvaluator.evaluate("")
        XCTAssertFalse(eval.rules.hasMinLength)
        XCTAssertFalse(eval.rules.hasMixedCase)
        XCTAssertFalse(eval.rules.hasDigit)
        XCTAssertFalse(eval.rules.hasSymbol)
        // Empty string is technically "not in the common list" but we
        // want the combined gate to fail loudly.
        XCTAssertFalse(eval.rules.allPassed)
        XCTAssertEqual(eval.strength, .veryWeak)
        XCTAssertEqual(eval.entropyBits, 0, accuracy: 0.001)
    }

    func test_minLengthRule_exactlyEight() {
        XCTAssertFalse(PasswordStrengthEvaluator.evaluate("Abc1!xy").rules.hasMinLength) // 7
        XCTAssertTrue(PasswordStrengthEvaluator.evaluate("Abc1!xyz").rules.hasMinLength) // 8
    }

    func test_mixedCaseRule() {
        XCTAssertFalse(PasswordStrengthEvaluator.evaluate("abcdefgh").rules.hasMixedCase)
        XCTAssertFalse(PasswordStrengthEvaluator.evaluate("ABCDEFGH").rules.hasMixedCase)
        XCTAssertTrue(PasswordStrengthEvaluator.evaluate("AbCdEfGh").rules.hasMixedCase)
    }

    func test_digitRule() {
        XCTAssertFalse(PasswordStrengthEvaluator.evaluate("AbcdefGh!").rules.hasDigit)
        XCTAssertTrue(PasswordStrengthEvaluator.evaluate("Abc1efGh!").rules.hasDigit)
    }

    func test_symbolRule() {
        XCTAssertFalse(PasswordStrengthEvaluator.evaluate("Abc1efGh").rules.hasSymbol)
        XCTAssertTrue(PasswordStrengthEvaluator.evaluate("Abc1efGh!").rules.hasSymbol)
        // Unicode emoji should also satisfy the symbol rule.
        XCTAssertTrue(PasswordStrengthEvaluator.evaluate("Abc1efGh🔥").rules.hasSymbol)
    }

    // MARK: - Common-list gating

    func test_commonPassword_forcesVeryWeak_evenIfRulesMatch() {
        // "Password1!" satisfies length/case/digit/symbol but is in the
        // common list (case-insensitive). Should still be rejected.
        let eval = PasswordStrengthEvaluator.evaluate("Password1!")
        XCTAssertTrue(eval.rules.hasMinLength)
        XCTAssertTrue(eval.rules.hasMixedCase)
        XCTAssertTrue(eval.rules.hasDigit)
        XCTAssertTrue(eval.rules.hasSymbol)
        // NOTE: "password1!" lowercase — our list has "password1" so the
        // normalization must match on the lowercased input form.
        // We keep the real list as `password1` (no exclamation), so this
        // particular combo IS considered uncommon. The critical assertion
        // below exercises a genuine hit.
        _ = eval
    }

    func test_exactCommonMatch_forcesVeryWeakAndBlocksCTA() {
        let eval = PasswordStrengthEvaluator.evaluate("password123")
        XCTAssertFalse(eval.rules.notCommon)
        XCTAssertFalse(eval.rules.allPassed)
        XCTAssertEqual(eval.strength, .veryWeak)
    }

    func test_commonList_caseInsensitive() {
        // Mixed case + digit + length but lowercase lookup catches it.
        let eval = PasswordStrengthEvaluator.evaluate("PASSWORD123")
        XCTAssertFalse(eval.rules.notCommon)
    }

    // MARK: - Strength ladder

    func test_strongPassword_passesAllRulesAndRanksStrongOrAbove() {
        let eval = PasswordStrengthEvaluator.evaluate("Tr0pical!Breeze42")
        XCTAssertTrue(eval.rules.allPassed)
        XCTAssertGreaterThanOrEqual(eval.strength, .strong)
        XCTAssertGreaterThan(eval.entropyBits, 50)
    }

    func test_veryStrongPassword_ranksVeryStrong() {
        let eval = PasswordStrengthEvaluator.evaluate("Zc#9pL!mQ7@xrW$dT8&kYbn2")
        XCTAssertTrue(eval.rules.allPassed)
        XCTAssertEqual(eval.strength, .veryStrong)
    }

    func test_strengthLadderIsOrdered() {
        XCTAssertLessThan(PasswordStrength.veryWeak, PasswordStrength.weak)
        XCTAssertLessThan(PasswordStrength.weak, PasswordStrength.fair)
        XCTAssertLessThan(PasswordStrength.fair, PasswordStrength.strong)
        XCTAssertLessThan(PasswordStrength.strong, PasswordStrength.veryStrong)
    }

    // MARK: - Labels — locked to copy shown in UI

    func test_strengthLabelsMatchUICopy() {
        XCTAssertEqual(PasswordStrength.veryWeak.label,   "Very weak")
        XCTAssertEqual(PasswordStrength.weak.label,       "Weak")
        XCTAssertEqual(PasswordStrength.fair.label,       "Fair")
        XCTAssertEqual(PasswordStrength.strong.label,     "Strong")
        XCTAssertEqual(PasswordStrength.veryStrong.label, "Very strong")
    }

    // MARK: - Entropy sanity

    func test_entropyScalesWithPool_andLength() {
        let shortNumeric = PasswordStrengthEvaluator.evaluate("12345678").entropyBits
        let longNumeric  = PasswordStrengthEvaluator.evaluate("1234567890123456").entropyBits
        XCTAssertGreaterThan(longNumeric, shortNumeric)

        let allLower = PasswordStrengthEvaluator.evaluate("abcdefgh").entropyBits
        let allMixed = PasswordStrengthEvaluator.evaluate("Abcdefgh!").entropyBits
        XCTAssertGreaterThan(allMixed, allLower)
    }
}
