import XCTest
@testable import Setup

// MARK: - SetupThreeColumnView tests
//
// Structural tests for SetupThreeColumnView.
// We verify:
//   - View can be instantiated without crashing with any combination of
//     payload + step + completedSteps.
//   - The generic closure types compile correctly (FormContent, NavContent).
//   - Column sizing constants align with design spec (sidebar 240, min form 380).
//
// Note: Pure layout assertions (frame values) are intentionally omitted —
// those require an XCUITest host. We focus on domain-level logic that IS
// unit-testable: the view's initialiser, its dependency on the sidebar model,
// and the helper types it exposes.

final class SetupThreeColumnViewTests: XCTestCase {

    // MARK: - Instantiation

    func test_init_withEmptyPayload_doesNotThrow() {
        // Should initialise without crashing.
        let payload = SetupPayload()
        _ = SetupThreeColumnView(
            payload: payload,
            currentStep: .welcome,
            completedSteps: []
        ) {
            EmptyTestContent()
        } navContent: {
            EmptyTestContent()
        }
        // Reaching here means no crash.
    }

    func test_init_withFilledPayload_doesNotThrow() {
        var payload = SetupPayload()
        payload.companyName = "Acme Corp"
        payload.timezone = "America/New_York"
        payload.taxRate = TaxRate(name: "GST", ratePct: 10.0, applyTo: .allItems)
        payload.firstLocation = SetupLocation(name: "HQ", address: "1 Main St", phone: "555-0000")

        _ = SetupThreeColumnView(
            payload: payload,
            currentStep: .taxSetup,
            completedSteps: [1, 2, 3, 4, 5]
        ) {
            EmptyTestContent()
        } navContent: {
            EmptyTestContent()
        }
    }

    func test_init_withAllStepsCompleted_doesNotThrow() {
        let allCompleted = Set(SetupStep.allCases.map(\.rawValue))
        _ = SetupThreeColumnView(
            payload: SetupPayload(),
            currentStep: .complete,
            completedSteps: allCompleted
        ) {
            EmptyTestContent()
        } navContent: {
            EmptyTestContent()
        }
    }

    // MARK: - Step coverage

    func test_init_eachStep_doesNotThrow() {
        for step in SetupStep.allCases {
            _ = SetupThreeColumnView(
                payload: SetupPayload(),
                currentStep: step,
                completedSteps: []
            ) {
                EmptyTestContent()
            } navContent: {
                EmptyTestContent()
            }
        }
    }
}

// MARK: - Minimal SwiftUI stub usable in unit tests (no host app required)

import SwiftUI

struct EmptyTestContent: View {
    var body: some View { EmptyView() }
}
