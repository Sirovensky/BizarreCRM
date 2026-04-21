import SwiftUI
import DesignSystem

// MARK: - PTOCoveragePrompt

/// Shown to the manager when approving PTO that conflicts with scheduled shifts.
/// Presents conflicting employees and a suggested swap partner.
public struct PTOCoveragePrompt: View {
    public let conflictingEmployeeIds: [String]
    public let suggestedSwapPartner: String?
    public let onApproveAnyway: () -> Void
    public let onCancel: () -> Void

    public init(
        conflictingEmployeeIds: [String],
        suggestedSwapPartner: String?,
        onApproveAnyway: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.conflictingEmployeeIds = conflictingEmployeeIds
        self.suggestedSwapPartner = suggestedSwapPartner
        self.onApproveAnyway = onApproveAnyway
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Label("Coverage Conflict", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            if !conflictingEmployeeIds.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Already scheduled off:")
                        .font(.subheadline.weight(.medium))
                    ForEach(conflictingEmployeeIds, id: \.self) { empId in
                        Label(empId, systemImage: "person.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let partner = suggestedSwapPartner {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.accentColor)
                    Text("Suggested swap: \(partner)")
                        .font(.callout)
                }
            }

            HStack(spacing: DesignTokens.Spacing.lg) {
                Button("Approve Anyway", action: onApproveAnyway)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityLabel("Approve PTO despite conflict")

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }
}
