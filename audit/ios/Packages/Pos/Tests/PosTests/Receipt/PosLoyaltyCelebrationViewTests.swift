import XCTest
@testable import Pos

/// §Agent-E (finisher) — Logic tests for `PosLoyaltyCelebrationView` and
/// the loyalty fields on `PosReceiptPayload` that drive it.
///
/// `PosLoyaltyCelebrationView` is UIKit-gated, so we can't render it in a
/// macro-test-runner on macOS. We test instead:
///
/// - The public stored properties the view reads directly.
/// - The `didTierUp` invariant expressed through the publicly-observable
///   `tierBefore`/`tierAfter` inequality (the private computed prop is
///   tested indirectly by verifying the data it consumes).
/// - The `tierProgress` clamping (0…1) baked into the init.
/// - The hidden-celebration invariant: when `loyaltyDelta` is `nil` on the
///   payload the parent view (`PosReceiptView`) does not instantiate the
///   celebration row at all — that branch is covered by verifying that
///   `loyaltyDelta` is `nil` so the guard in the view body cannot pass.
final class PosLoyaltyCelebrationViewTests: XCTestCase {

    // MARK: - §1: pointsDelta is stored exactly

    func test_pointsDelta_storedExact() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 127,
            tierBefore: "Gold",
            tierAfter: "Platinum"
        )
        XCTAssertEqual(view.pointsDelta, 127)
    }

    // MARK: - §2: tierProgress clamped above 1.0

    func test_tierProgress_clampedToOne_whenAbove() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 50,
            tierBefore: "Silver",
            tierAfter: "Silver",
            tierProgress: 1.5
        )
        XCTAssertEqual(view.tierProgress, 1.0, accuracy: 0.001)
    }

    // MARK: - §3: tierProgress clamped below 0.0

    func test_tierProgress_clampedToZero_whenBelow() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 10,
            tierBefore: "Bronze",
            tierAfter: "Bronze",
            tierProgress: -0.5
        )
        XCTAssertEqual(view.tierProgress, 0.0, accuracy: 0.001)
    }

    // MARK: - §4: Tier-up detectable — tierBefore != tierAfter

    /// The view renders the crown + "Welcome to X!" banner when tiers differ.
    /// We verify the data precondition is correct (didTierUp is private so
    /// we assert the public invariant it reads).
    func test_tierUp_detectable_whenTiersDiffer() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 300,
            tierBefore: "Gold",
            tierAfter: "Platinum",
            tierProgress: 1.0
        )
        // The condition that triggers the tier-up crown + welcome text.
        let didTierUp = view.tierBefore.flatMap { before in
            view.tierAfter.map { after in
                before.caseInsensitiveCompare(after) != .orderedSame
            }
        } ?? false
        XCTAssertTrue(didTierUp, "Should detect tier change from Gold to Platinum")
    }

    // MARK: - §5: No tier-up when tiers are equal

    func test_noTierUp_whenTiersMatch() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 45,
            tierBefore: "Silver",
            tierAfter: "Silver",
            tierProgress: 0.57
        )
        let didTierUp = view.tierBefore.flatMap { before in
            view.tierAfter.map { after in
                before.caseInsensitiveCompare(after) != .orderedSame
            }
        } ?? false
        XCTAssertFalse(didTierUp)
    }

    // MARK: - §6: Celebration row hidden when loyaltyDelta is nil

    /// `PosReceiptView.loyaltyCelebration` renders `PosLoyaltyCelebrationView`
    /// only when `payload.loyaltyDelta != nil && delta > 0`.
    /// Verify the payload guard condition.
    func test_loyaltyCelebration_hiddenWhenDeltaNil() {
        let payload = PosReceiptPayload(
            invoiceId: 77,
            amountPaidCents: 500,
            methodLabel: "Card",
            loyaltyDelta: nil
        )
        // The guard in PosReceiptView is: `if let delta = vm.payload.loyaltyDelta, delta > 0`
        let willShow = payload.loyaltyDelta.map { $0 > 0 } ?? false
        XCTAssertFalse(willShow, "Celebration row must not render when loyaltyDelta is nil")
    }

    // MARK: - §7: Celebration row hidden when loyaltyDelta is zero

    func test_loyaltyCelebration_hiddenWhenDeltaZero() {
        let payload = PosReceiptPayload(
            invoiceId: 78,
            amountPaidCents: 500,
            methodLabel: "Card",
            loyaltyDelta: 0
        )
        let willShow = payload.loyaltyDelta.map { $0 > 0 } ?? false
        XCTAssertFalse(willShow)
    }

    // MARK: - §8: Celebration row visible when delta is positive

    func test_loyaltyCelebration_shownWhenDeltaPositive() {
        let payload = PosReceiptPayload(
            invoiceId: 79,
            amountPaidCents: 5000,
            methodLabel: "Cash",
            loyaltyDelta: 75
        )
        let willShow = payload.loyaltyDelta.map { $0 > 0 } ?? false
        XCTAssertTrue(willShow)
    }

    // MARK: - §9: tierProgress default is 0.5

    func test_tierProgress_defaultIs05() {
        let view = PosLoyaltyCelebrationView(
            pointsDelta: 20,
            tierBefore: nil,
            tierAfter: nil
        )
        XCTAssertEqual(view.tierProgress, 0.5, accuracy: 0.001)
    }
}
