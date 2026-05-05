import XCTest
@testable import Tickets

/// §4.3 + §4.5 — TicketStateMachine unit tests.
///
/// Coverage goals (≥80%):
///  - Every legal transition succeeds and lands on the correct target status.
///  - Every guard-rail (illegal transition) returns `.illegalTransition`.
///  - `allowedTransitions(from:)` returns the expected set for each status.
///  - Terminal statuses expose an empty allowed-transitions array.
///  - `StateMachineError.errorDescription` produces a non-empty string.
final class TicketStateMachineTests: XCTestCase {

    // MARK: — Intake

    func test_intake_diagnose_yieldsDignosing() {
        let result = TicketStateMachine.apply(.diagnose, to: .intake)
        XCTAssertEqual(result, .success(.diagnosing))
    }

    func test_intake_hold_yieldsOnHold() {
        let result = TicketStateMachine.apply(.hold, to: .intake)
        XCTAssertEqual(result, .success(.onHold))
    }

    func test_intake_cancel_yieldsCanceled() {
        let result = TicketStateMachine.apply(.cancel, to: .intake)
        XCTAssertEqual(result, .success(.canceled))
    }

    func test_intake_orderParts_isIllegal() {
        let result = TicketStateMachine.apply(.orderParts, to: .intake)
        XCTAssertEqual(result, .failure(.illegalTransition(from: .intake, transition: .orderParts)))
    }

    func test_intake_pickup_isIllegal() {
        let result = TicketStateMachine.apply(.pickup, to: .intake)
        XCTAssertEqual(result, .failure(.illegalTransition(from: .intake, transition: .pickup)))
    }

    func test_intake_allowedTransitions() {
        let allowed = TicketStateMachine.allowedTransitions(from: .intake)
        XCTAssertEqual(Set(allowed), [.diagnose, .hold, .cancel])
    }

    // MARK: — Diagnosing

    func test_diagnosing_orderParts_yieldsAwaitingParts() {
        let result = TicketStateMachine.apply(.orderParts, to: .diagnosing)
        XCTAssertEqual(result, .success(.awaitingParts))
    }

    func test_diagnosing_requestApproval_yieldsAwaitingApproval() {
        let result = TicketStateMachine.apply(.requestApproval, to: .diagnosing)
        XCTAssertEqual(result, .success(.awaitingApproval))
    }

    func test_diagnosing_approveAndRepair_yieldsInRepair() {
        let result = TicketStateMachine.apply(.approveAndRepair, to: .diagnosing)
        XCTAssertEqual(result, .success(.inRepair))
    }

    func test_diagnosing_hold_yieldsOnHold() {
        let result = TicketStateMachine.apply(.hold, to: .diagnosing)
        XCTAssertEqual(result, .success(.onHold))
    }

    func test_diagnosing_cancel_yieldsCanceled() {
        let result = TicketStateMachine.apply(.cancel, to: .diagnosing)
        XCTAssertEqual(result, .success(.canceled))
    }

    func test_diagnosing_diagnose_isIllegal() {
        let result = TicketStateMachine.apply(.diagnose, to: .diagnosing)
        XCTAssertEqual(result, .failure(.illegalTransition(from: .diagnosing, transition: .diagnose)))
    }

    func test_diagnosing_allowedTransitions() {
        let allowed = TicketStateMachine.allowedTransitions(from: .diagnosing)
        XCTAssertEqual(Set(allowed), [.orderParts, .requestApproval, .approveAndRepair, .hold, .cancel])
    }

    // MARK: — Awaiting Parts

    func test_awaitingParts_approveAndRepair_yieldsInRepair() {
        let result = TicketStateMachine.apply(.approveAndRepair, to: .awaitingParts)
        XCTAssertEqual(result, .success(.inRepair))
    }

    func test_awaitingParts_hold_yieldsOnHold() {
        let result = TicketStateMachine.apply(.hold, to: .awaitingParts)
        XCTAssertEqual(result, .success(.onHold))
    }

    func test_awaitingParts_cancel_yieldsCanceled() {
        let result = TicketStateMachine.apply(.cancel, to: .awaitingParts)
        XCTAssertEqual(result, .success(.canceled))
    }

    func test_awaitingParts_pickup_isIllegal() {
        let result = TicketStateMachine.apply(.pickup, to: .awaitingParts)
        XCTAssertEqual(result, .failure(.illegalTransition(from: .awaitingParts, transition: .pickup)))
    }

    func test_awaitingParts_allowedTransitions() {
        let allowed = TicketStateMachine.allowedTransitions(from: .awaitingParts)
        XCTAssertEqual(Set(allowed), [.approveAndRepair, .hold, .cancel])
    }

    // MARK: — Awaiting Approval

    func test_awaitingApproval_approveAndRepair_yieldsInRepair() {
        let result = TicketStateMachine.apply(.approveAndRepair, to: .awaitingApproval)
        XCTAssertEqual(result, .success(.inRepair))
    }

    func test_awaitingApproval_hold_yieldsOnHold() {
        let result = TicketStateMachine.apply(.hold, to: .awaitingApproval)
        XCTAssertEqual(result, .success(.onHold))
    }

    func test_awaitingApproval_cancel_yieldsCanceled() {
        let result = TicketStateMachine.apply(.cancel, to: .awaitingApproval)
        XCTAssertEqual(result, .success(.canceled))
    }

    func test_awaitingApproval_finishRepair_isIllegal() {
        let result = TicketStateMachine.apply(.finishRepair, to: .awaitingApproval)
        XCTAssertEqual(result, .failure(.illegalTransition(from: .awaitingApproval, transition: .finishRepair)))
    }

    func test_awaitingApproval_allowedTransitions() {
        let allowed = TicketStateMachine.allowedTransitions(from: .awaitingApproval)
        XCTAssertEqual(Set(allowed), [.approveAndRepair, .hold, .cancel])
    }

    // MARK: — In Repair

    func test_inRepair_finishRepair_yieldsReadyForPickup() {
        let result = TicketStateMachine.apply(.finishRepair, to: .inRepair)
        XCTAssertEqual(result, .success(.readyForPickup))
    }

    func test_inRepair_orderParts_yieldsAwaitingParts() {
        let result = TicketStateMachine.apply(.orderParts, to: .inRepair)
        XCTAssertEqual(result, .success(.awaitingParts))
    }

    func test_inRepair_hold_yieldsOnHold() {
        let result = TicketStateMachine.apply(.hold, to: .inRepair)
        XCTAssertEqual(result, .success(.onHold))
    }

    func test_inRepair_cancel_yieldsCanceled() {
        let result = TicketStateMachine.apply(.cancel, to: .inRepair)
        XCTAssertEqual(result, .success(.canceled))
    }

    func test_inRepair_diagnose_isIllegal() {
        let result = TicketStateMachine.apply(.diagnose, to: .inRepair)
        XCTAssertEqual(result, .failure(.illegalTransition(from: .inRepair, transition: .diagnose)))
    }

    func test_inRepair_allowedTransitions() {
        let allowed = TicketStateMachine.allowedTransitions(from: .inRepair)
        XCTAssertEqual(Set(allowed), [.finishRepair, .orderParts, .hold, .cancel])
    }

    // MARK: — Ready for Pickup

    func test_readyForPickup_pickup_yieldsCompleted() {
        let result = TicketStateMachine.apply(.pickup, to: .readyForPickup)
        XCTAssertEqual(result, .success(.completed))
    }

    func test_readyForPickup_cancel_yieldsCanceled() {
        let result = TicketStateMachine.apply(.cancel, to: .readyForPickup)
        XCTAssertEqual(result, .success(.canceled))
    }

    func test_readyForPickup_hold_isIllegal() {
        let result = TicketStateMachine.apply(.hold, to: .readyForPickup)
        XCTAssertEqual(result, .failure(.illegalTransition(from: .readyForPickup, transition: .hold)))
    }

    func test_readyForPickup_allowedTransitions() {
        let allowed = TicketStateMachine.allowedTransitions(from: .readyForPickup)
        XCTAssertEqual(Set(allowed), [.pickup, .cancel])
    }

    // MARK: — On Hold

    func test_onHold_resume_yieldsDignosing() {
        let result = TicketStateMachine.apply(.resume, to: .onHold)
        XCTAssertEqual(result, .success(.diagnosing))
    }

    func test_onHold_cancel_yieldsCanceled() {
        let result = TicketStateMachine.apply(.cancel, to: .onHold)
        XCTAssertEqual(result, .success(.canceled))
    }

    func test_onHold_finishRepair_isIllegal() {
        let result = TicketStateMachine.apply(.finishRepair, to: .onHold)
        XCTAssertEqual(result, .failure(.illegalTransition(from: .onHold, transition: .finishRepair)))
    }

    func test_onHold_allowedTransitions() {
        let allowed = TicketStateMachine.allowedTransitions(from: .onHold)
        XCTAssertEqual(Set(allowed), [.resume, .cancel])
    }

    // MARK: — Terminal states

    func test_completed_isTerminal() {
        XCTAssertTrue(TicketStatus.completed.isTerminal)
    }

    func test_canceled_isTerminal() {
        XCTAssertTrue(TicketStatus.canceled.isTerminal)
    }

    func test_completed_allowedTransitions_isEmpty() {
        XCTAssertTrue(TicketStateMachine.allowedTransitions(from: .completed).isEmpty)
    }

    func test_canceled_allowedTransitions_isEmpty() {
        XCTAssertTrue(TicketStateMachine.allowedTransitions(from: .canceled).isEmpty)
    }

    func test_completed_anyTransition_isIllegal() {
        for transition in TicketTransition.allCases {
            let result = TicketStateMachine.apply(transition, to: .completed)
            if case .failure = result { /* expected */ } else {
                XCTFail("Expected illegal transition from completed via \(transition)")
            }
        }
    }

    func test_canceled_anyTransition_isIllegal() {
        for transition in TicketTransition.allCases {
            let result = TicketStateMachine.apply(transition, to: .canceled)
            if case .failure = result { /* expected */ } else {
                XCTFail("Expected illegal transition from canceled via \(transition)")
            }
        }
    }

    // MARK: — Non-terminal statuses

    func test_nonTerminalStatuses_areNotTerminal() {
        let nonTerminal: [TicketStatus] = [
            .intake, .diagnosing, .awaitingParts, .awaitingApproval,
            .inRepair, .readyForPickup, .onHold
        ]
        for status in nonTerminal {
            XCTAssertFalse(status.isTerminal, "\(status) should not be terminal")
        }
    }

    // MARK: — Error description

    func test_illegalTransitionError_hasDescription() {
        let error = StateMachineError.illegalTransition(from: .intake, transition: .pickup)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    // MARK: — Display names sanity

    func test_allStatuses_haveNonEmptyDisplayName() {
        for status in TicketStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty, "\(status) has empty displayName")
        }
    }

    func test_allTransitions_haveNonEmptyDisplayName() {
        for transition in TicketTransition.allCases {
            XCTAssertFalse(transition.displayName.isEmpty, "\(transition) has empty displayName")
        }
    }

    func test_allTransitions_haveNonEmptySystemImage() {
        for transition in TicketTransition.allCases {
            XCTAssertFalse(transition.systemImage.isEmpty, "\(transition) has empty systemImage")
        }
    }

    // MARK: — Codable round-trip

    func test_ticketStatus_codableRoundTrip() throws {
        for status in TicketStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(TicketStatus.self, from: encoded)
            XCTAssertEqual(decoded, status)
        }
    }

    // MARK: — Full lifecycle happy path

    func test_fullLifecycle_intakeToCompleted() {
        var status = TicketStatus.intake

        let steps: [TicketTransition] = [
            .diagnose,
            .requestApproval,
            .approveAndRepair,
            .finishRepair,
            .pickup
        ]

        let expectedResults: [TicketStatus] = [
            .diagnosing,
            .awaitingApproval,
            .inRepair,
            .readyForPickup,
            .completed
        ]

        for (transition, expected) in zip(steps, expectedResults) {
            switch TicketStateMachine.apply(transition, to: status) {
            case .success(let next):
                XCTAssertEqual(next, expected)
                status = next
            case .failure(let err):
                XCTFail("Unexpected failure at \(transition): \(err)")
            }
        }
    }

    func test_holdAndResume_returnsToDignosing() {
        let holdResult = TicketStateMachine.apply(.hold, to: .diagnosing)
        guard case .success(let onHold) = holdResult else {
            XCTFail("hold from diagnosing should succeed")
            return
        }
        XCTAssertEqual(onHold, .onHold)

        let resumeResult = TicketStateMachine.apply(.resume, to: onHold)
        guard case .success(let resumed) = resumeResult else {
            XCTFail("resume from onHold should succeed")
            return
        }
        XCTAssertEqual(resumed, .diagnosing)
    }
}
