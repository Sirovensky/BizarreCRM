import SwiftUI
import Core
import DesignSystem

// MARK: - SetupThreeColumnView  (§22 iPad polish)
//
// A self-contained 3-column wrapper for the Setup Wizard on iPad (width ≥ 900 pt).
// Layout: [Steps sidebar 240pt] | [Step form flexible] | [Live-preview pane 300pt]
//
// Callers embed their step form and nav bar via the `formContent` and `navContent`
// trailing closures. The sidebar and preview pane are supplied by this view.
//
// Liquid Glass chrome is applied per CLAUDE.md rules:
//  - sidebar column  → .brandGlass(.regular)
//  - preview column  → .brandGlass(.regular)
//  - outer shell     → .thickMaterial RoundedRectangle
//
// Usage:
//   SetupThreeColumnView(
//       payload: vm.wizardPayload,
//       currentStep: vm.currentStep,
//       completedSteps: vm.completedSteps
//   ) {
//       stepBodyView         // formContent
//   } navContent: {
//       navBarView           // navContent
//   }

public struct SetupThreeColumnView<FormContent: View, NavContent: View>: View {

    // MARK: - Properties

    public let payload: SetupPayload
    public let currentStep: SetupStep
    public let completedSteps: Set<Int>

    private let formContent: FormContent
    private let navContent: NavContent

    // MARK: - Init

    public init(
        payload: SetupPayload,
        currentStep: SetupStep,
        completedSteps: Set<Int>,
        @ViewBuilder formContent: () -> FormContent,
        @ViewBuilder navContent: () -> NavContent
    ) {
        self.payload = payload
        self.currentStep = currentStep
        self.completedSteps = completedSteps
        self.formContent = formContent()
        self.navContent = navContent()
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
                .frame(width: 240)

            columnDivider

            formColumn
                .frame(minWidth: 380, maxWidth: 520)

            columnDivider

            previewColumn
                .frame(minWidth: 280, idealWidth: 320)
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sidebar column

    private var sidebarColumn: some View {
        SetupSkipAdvancedSidebar(
            currentStep: currentStep,
            completedSteps: completedSteps
        )
        .brandGlass(.regular, in: Rectangle())
    }

    // MARK: - Form column

    private var formColumn: some View {
        VStack(spacing: 0) {
            formContent
            navContent
        }
    }

    // MARK: - Preview column

    private var previewColumn: some View {
        SetupLivePreviewPane(
            payload: payload,
            currentStep: currentStep
        )
        .brandGlass(.regular, in: Rectangle())
    }

    // MARK: - Helpers

    private var columnDivider: some View {
        Divider()
            .frame(maxHeight: .infinity)
    }
}
