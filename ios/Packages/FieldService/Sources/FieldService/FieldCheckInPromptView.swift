// §57.2 FieldCheckInPromptView — auto-prompts when geofence entered.
// Sheet presented modally over the map view.

import SwiftUI
import DesignSystem

// MARK: - FieldCheckInPromptView

/// Modal sheet prompting the technician to check in when they arrive
/// at the job site. Uses Liquid Glass on the sheet header.
public struct FieldCheckInPromptView: View {

    @State private var vm: FieldCheckInPromptViewModel

    public init(vm: FieldCheckInPromptViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Check In")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Later") { vm.dismiss() }
                    }
                }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:
            EmptyView()
        case .prompting(let apptId, let customerName, let address):
            promptBody(appointmentId: apptId, customerName: customerName, address: address)
        case .checkingIn:
            VStack(spacing: DesignTokens.Spacing.lg) {
                ProgressView("Verifying location…")
                    .font(.brandBodyMedium())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .checkedIn:
            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreSuccess)
                Text("Checked In")
                    .font(.brandTitleMedium())
                Text("Your arrival has been recorded.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreError)
                Text(msg)
                    .font(.brandBodyMedium())
                    .multilineTextAlignment(.center)
                Button("Try Again") { vm.retryReset() }
                    .buttonStyle(.brandGlassProminent)
                    .tint(.bizarreOrange)
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func promptBody(
        appointmentId: Int64,
        customerName: String,
        address: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            // Glass header chip.
            HStack {
                Image(systemName: "location.fill")
                    .foregroundStyle(.bizarreOrange)
                Text("You're near the job site")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.primary)
            }
            .padding(DesignTokens.Spacing.md)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                LabeledRow(label: "Customer", value: customerName)
                LabeledRow(label: "Address", value: address)
            }

            Spacer()

            Button("Check In Now") {
                Task { await vm.confirmCheckIn(appointmentId: appointmentId, address: address) }
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .accessibilityHint("Verifies your GPS location and records your arrival")
        }
        .padding(DesignTokens.Spacing.xl)
    }
}

// MARK: - LabeledRow

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.brandTitleMedium())
                .foregroundStyle(.primary)
        }
    }
}
