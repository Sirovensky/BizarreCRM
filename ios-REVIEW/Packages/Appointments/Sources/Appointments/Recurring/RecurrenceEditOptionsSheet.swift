import SwiftUI
import DesignSystem

// MARK: - RecurrenceEditScope

public enum RecurrenceEditScope: Sendable {
    /// Change only this occurrence.
    case thisOccurrence
    /// Change this and all future occurrences.
    case thisAndFuture
    /// Change the entire series.
    case all
}

// MARK: - RecurrenceEditOptionsSheet

/// Presented when the user edits an instance of a recurring appointment.
/// Asks which scope the edit applies to.
public struct RecurrenceEditOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let onSelect: (RecurrenceEditScope) -> Void

    public init(onSelect: @escaping (RecurrenceEditScope) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    Divider()
                    optionsList
                    Spacer()
                }
            }
            .navigationTitle("Edit Recurring Appointment")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("This is a recurring appointment.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
            Text("Which appointments would you like to edit?")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.lg)
    }

    private var optionsList: some View {
        VStack(spacing: BrandSpacing.xs) {
            OptionButton(
                title: "Change this occurrence",
                subtitle: "Only the selected appointment is affected.",
                icon: "calendar"
            ) {
                onSelect(.thisOccurrence)
                dismiss()
            }
            OptionButton(
                title: "Change this and future",
                subtitle: "This and all following appointments are changed.",
                icon: "calendar.badge.plus"
            ) {
                onSelect(.thisAndFuture)
                dismiss()
            }
            OptionButton(
                title: "Change all",
                subtitle: "Every appointment in the series is changed.",
                icon: "calendar.badge.clock"
            ) {
                onSelect(.all)
                dismiss()
            }
        }
        .padding(.horizontal, BrandSpacing.md)
    }
}

// MARK: - OptionButton

private struct OptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(title)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(subtitle)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
