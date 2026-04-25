#if canImport(UIKit)
import SwiftUI
import Networking
import Core
import DesignSystem

// MARK: - RepairFlowAdapter
//
// Bridges `PosRepairFlowCoordinator` to the existing `PosView` routing model.
//
// Usage in PosView:
//
//   @State private var repairFlowCoordinator: PosRepairFlowCoordinator?
//
//   .sheet(item: $repairFlowCoordinator) { coordinator in
//       RepairFlowAdapter(coordinator: coordinator)
//   }
//
// The adapter owns the NavigationStack + step routing so `PosView` only
// needs to create the coordinator and present the sheet.

public struct RepairFlowAdapter: View {

    @Bindable private var coordinator: PosRepairFlowCoordinator
    private let devicePickerVM: PosDevicePickerViewModel

    /// Standard init — provide a live APIClient and the PosDevicePickerRepository.
    public init(coordinator: PosRepairFlowCoordinator, devicePickerVM: PosDevicePickerViewModel) {
        self.coordinator = coordinator
        self.devicePickerVM = devicePickerVM
    }

    public var body: some View {
        NavigationStack {
            stepContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            coordinator.cancel()
                        }
                        .accessibilityLabel("Cancel repair flow")
                        .accessibilityIdentifier("repairFlow.cancel")
                    }
                }
        }
        .interactiveDismissDisabled(coordinator.savedDraftId != nil)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch coordinator.currentStep {
        case .pickDevice:
            PosRepairDevicePickerView(
                coordinator: coordinator,
                devicePickerVM: devicePickerVM
            )

        case .describeIssue:
            PosRepairSymptomView(coordinator: coordinator)

        case .diagnosticQuote:
            PosRepairQuoteView(coordinator: coordinator)

        case .deposit:
            PosRepairDepositView(coordinator: coordinator)
        }
    }
}

// MARK: - PosRepairFlowCoordinator + Identifiable

extension PosRepairFlowCoordinator: Identifiable {
    nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

// MARK: - PosView extension hook
//
// Convenience factory so PosView can start a repair flow with a single call.
// Place the sheet modifier on PosView.body and call `startRepairFlow` from
// the "New repair" toolbar button.
//
// Example:
//   @State private var repairCoordinator: PosRepairFlowCoordinator?
//
//   Button("New repair") {
//       repairCoordinator = PosRepairRouter.makeCoordinator(
//           customerId: cart.customer?.id ?? 0,
//           api: api,
//           devicePickerRepo: PosDevicePickerRepositoryImpl(api: api),
//           onCancel: { repairCoordinator = nil },
//           onComplete: { invoiceId in repairCoordinator = nil }
//       )
//   }

@MainActor
public enum PosRepairRouter {
    /// Creates a fully wired coordinator ready for presentation.
    /// `customerDisplayName` populates the nav-bar chip on repair step screens
    /// (mockup spec for 1b–1e shows "New repair · {customer}").
    public static func makeCoordinator(
        customerId: Int64,
        customerDisplayName: String?,
        api: any APIClient,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (Int64) -> Void
    ) -> PosRepairFlowCoordinator {
        let coordinator = PosRepairFlowCoordinator(customerId: customerId, api: api)
        coordinator.customerDisplayName = customerDisplayName
        coordinator.onCancel = onCancel
        coordinator.onComplete = onComplete
        return coordinator
    }
}
#endif
