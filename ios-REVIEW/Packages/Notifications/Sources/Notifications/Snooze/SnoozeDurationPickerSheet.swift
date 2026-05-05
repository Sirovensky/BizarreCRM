import SwiftUI
import Observation
import DesignSystem

// MARK: - SnoozeDurationPickerViewModel

@MainActor
@Observable
public final class SnoozeDurationPickerViewModel {

    // MARK: - State

    public private(set) var selectedDuration: SnoozeDuration = .fifteenMinutes
    public var customMinutes: Int = 30

    public var presets: [SnoozeDuration] {
        [.fifteenMinutes, .oneHour, .tomorrowMorning]
    }

    // MARK: - Init

    public init(initialDuration: SnoozeDuration = .fifteenMinutes) {
        self.selectedDuration = initialDuration
    }

    // MARK: - Selection

    public func select(_ duration: SnoozeDuration) {
        selectedDuration = duration
    }

    public func selectCustom() {
        selectedDuration = .custom(minutes: customMinutes)
    }

    public var isCustomSelected: Bool {
        if case .custom = selectedDuration { return true }
        return false
    }

    // MARK: - Fire date preview

    public func previewFireDate(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        selectedDuration.fireDate(from: now, calendar: calendar)
    }

    public func fireTimeLabel(from now: Date = Date(), calendar: Calendar = .current) -> String {
        let date = previewFireDate(from: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let today = calendar.isDateInToday(date)
        let tomorrow = calendar.isDateInTomorrow(date)
        let prefix = today ? "Today" : (tomorrow ? "Tomorrow" : formatter.string(from: date))
        if today || tomorrow {
            return "\(prefix) at \(formatter.string(from: date))"
        }
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - SnoozeDurationPickerSheet

/// Bottom sheet for selecting a snooze duration.
/// Accessibility: each preset button announces its label + selected state.
public struct SnoozeDurationPickerSheet: View {

    @State private var vm: SnoozeDurationPickerViewModel
    let onSnooze: (SnoozeDuration) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        viewModel: SnoozeDurationPickerViewModel = SnoozeDurationPickerViewModel(),
        onSnooze: @escaping (SnoozeDuration) -> Void
    ) {
        _vm = State(wrappedValue: viewModel)
        self.onSnooze = onSnooze
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                presetButtons
                customSection
                fireTimePreview
                Spacer()
                snoozeButton
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Snooze Until")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Preset grid

    @ViewBuilder
    private var presetButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: BrandSpacing.sm) {
            ForEach(vm.presets, id: \.displayName) { preset in
                presetTile(preset)
            }
        }
    }

    @ViewBuilder
    private func presetTile(_ duration: SnoozeDuration) -> some View {
        let isSelected = vm.selectedDuration == duration
        Button {
            vm.select(duration)
        } label: {
            Text(duration.displayName)
                .font(.brandLabelMedium())
                .foregroundStyle(isSelected ? Color.bizarreOnOrange : Color.bizarreOnSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .background(
                    isSelected ? Color.bizarreOrange : Color.bizarreSurface1,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(duration.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityHint("Snooze for \(duration.displayName)")
        .accessibilityIdentifier("snooze.preset.\(duration.displayName)")
    }

    // MARK: - Custom section

    @ViewBuilder
    private var customSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Custom")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)

            HStack {
                Slider(value: Binding(
                    get: { Double(vm.customMinutes) },
                    set: { vm.customMinutes = Int($0) }
                ), in: 5...240, step: 5)
                .tint(.bizarreOrange)
                .onChange(of: vm.customMinutes) { _, _ in vm.selectCustom() }

                Text("\(vm.customMinutes) min")
                    .font(.brandLabelMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Preview

    @ViewBuilder
    private var fireTimePreview: some View {
        HStack {
            Image(systemName: "alarm")
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)
            Text("Fires: \(vm.fireTimeLabel())")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("Notification will re-fire \(vm.fireTimeLabel())")
    }

    // MARK: - Snooze button

    @ViewBuilder
    private var snoozeButton: some View {
        Button {
            onSnooze(vm.selectedDuration)
            dismiss()
        } label: {
            Text("Snooze")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnOrange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
        }
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 14), tint: .bizarreOrange, interactive: true)
        .accessibilityLabel("Snooze for \(vm.selectedDuration.displayName)")
    }
}

// MARK: - Font helpers

private extension Font {
    static func brandLabelMedium() -> Font { .system(size: 14, weight: .medium) }
    static func brandLabelLarge() -> Font { .system(size: 15, weight: .semibold) }
    static func brandBodyLarge() -> Font { .system(size: 16) }
    static func brandHeadlineMedium() -> Font { .system(size: 17, weight: .semibold) }
}

// MARK: - SnoozeDuration Equatable

extension SnoozeDuration: Equatable {
    public static func == (lhs: SnoozeDuration, rhs: SnoozeDuration) -> Bool {
        switch (lhs, rhs) {
        case (.minutes(let a), .minutes(let b)): return a == b
        case (.custom(let a), .custom(let b)):   return a == b
        case (.tomorrowAt(let ah, let am), .tomorrowAt(let bh, let bm)):
            return ah == bh && am == bm
        default: return false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    Color.bizarreSurfaceBase
        .sheet(isPresented: .constant(true)) {
            SnoozeDurationPickerSheet { duration in
                print("Snooze: \(duration.displayName)")
            }
        }
}
#endif
