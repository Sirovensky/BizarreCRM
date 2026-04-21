import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class BusinessHoursViewModel {
    var days: [BusinessDay] = BusinessDay.defaults

    var isNextEnabled: Bool {
        Step5Validator.isNextEnabled(hours: days)
    }

    // MARK: Copy helpers

    /// Copies Monday's hours to Tuesday–Friday.
    func copyMonToWeekdays() {
        guard let mon = days.first(where: { $0.id == 1 }) else { return }
        days = days.map { day in
            guard day.id >= 2 && day.id <= 5 else { return day }
            return BusinessDay(weekday: day.id, isOpen: mon.isOpen, openAt: mon.openAt, closeAt: mon.closeAt)
        }
    }

    /// Copies Saturday's hours to Sunday.
    func copySatToSun() {
        guard let sat = days.first(where: { $0.id == 6 }) else { return }
        days = days.map { day in
            guard day.id == 7 else { return day }
            return BusinessDay(weekday: 7, isOpen: sat.isOpen, openAt: sat.openAt, closeAt: sat.closeAt)
        }
    }

    // MARK: Toggle / update per day (immutable update)

    func toggleOpen(for weekday: Int) {
        days = days.map { day in
            guard day.id == weekday else { return day }
            return BusinessDay(weekday: day.id, isOpen: !day.isOpen, openAt: day.openAt, closeAt: day.closeAt)
        }
    }

    func updateOpenAt(_ components: DateComponents, for weekday: Int) {
        days = days.map { day in
            guard day.id == weekday else { return day }
            return BusinessDay(weekday: day.id, isOpen: day.isOpen, openAt: components, closeAt: day.closeAt)
        }
    }

    func updateCloseAt(_ components: DateComponents, for weekday: Int) {
        days = days.map { day in
            guard day.id == weekday else { return day }
            return BusinessDay(weekday: day.id, isOpen: day.isOpen, openAt: day.openAt, closeAt: components)
        }
    }
}

// MARK: - View  (§36.2 Step 5 — Business Hours)

@MainActor
public struct BusinessHoursStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: ([BusinessDay]) -> Void

    @State private var vm = BusinessHoursViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping ([BusinessDay]) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                Text("Business Hours")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.top, BrandSpacing.lg)
                    .accessibilityAddTraits(.isHeader)

                Text("Set when your shop is open. Customers see these on estimates and appointment reminders.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)

                // MARK: Helper buttons

                HStack(spacing: BrandSpacing.sm) {
                    Button("Copy Mon to weekdays") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            vm.copyMonToWeekdays()
                        }
                    }
                    .buttonStyle(.brandGlass)
                    .font(.brandLabelLarge())
                    .accessibilityLabel("Copy Monday hours to Tuesday through Friday")

                    Button("Copy Sat to Sun") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            vm.copySatToSun()
                        }
                    }
                    .buttonStyle(.brandGlass)
                    .font(.brandLabelLarge())
                    .accessibilityLabel("Copy Saturday hours to Sunday")
                }

                // MARK: Day rows

                VStack(spacing: BrandSpacing.xs) {
                    ForEach(vm.days) { day in
                        DayHoursRow(
                            day: day,
                            onToggle: { vm.toggleOpen(for: day.id) },
                            onOpenAtChanged: { comps in vm.updateOpenAt(comps, for: day.id) },
                            onCloseAtChanged: { comps in vm.updateCloseAt(comps, for: day.id) }
                        )
                        if day.id < 7 {
                            Divider()
                                .background(Color.bizarreOutline.opacity(0.3))
                        }
                    }
                }
                .background(
                    Color.bizarreSurface1.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1)
                )
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: vm.isNextEnabled) { _, valid in
            onValidityChanged(valid)
        }
        .onAppear {
            onValidityChanged(vm.isNextEnabled)
        }
    }
}

// MARK: - DayHoursRow

@MainActor
private struct DayHoursRow: View {
    let day: BusinessDay
    let onToggle: () -> Void
    let onOpenAtChanged: (DateComponents) -> Void
    let onCloseAtChanged: (DateComponents) -> Void

    /// Helper: DateComponents → Date (today at that time)
    private func dateFromComponents(_ comps: DateComponents) -> Date {
        var full = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        full.hour   = comps.hour   ?? 9
        full.minute = comps.minute ?? 0
        return Calendar.current.date(from: full) ?? Date()
    }

    private func componentsFromDate(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: date)
    }

    var body: some View {
        VStack(spacing: BrandSpacing.xs) {
            HStack {
                Toggle(isOn: Binding(
                    get: { day.isOpen },
                    set: { _ in onToggle() }
                )) {
                    Text(day.weekdayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(day.isOpen ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                }
                .toggleStyle(.switch)
                .tint(.bizarreOrange)
                .accessibilityLabel("\(day.weekdayName) open")
                .accessibilityValue(day.isOpen ? "Open" : "Closed")
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.top, BrandSpacing.sm)

            if day.isOpen {
                HStack(spacing: BrandSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open")
                            .font(.brandLabelSmall())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        DatePicker(
                            "Open time",
                            selection: Binding(
                                get: { dateFromComponents(day.openAt) },
                                set: { onOpenAtChanged(componentsFromDate($0)) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .accessibilityLabel("Open time for \(day.weekdayName)")
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Close")
                            .font(.brandLabelSmall())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        DatePicker(
                            "Close time",
                            selection: Binding(
                                get: { dateFromComponents(day.closeAt) },
                                set: { onCloseAtChanged(componentsFromDate($0)) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .accessibilityLabel("Close time for \(day.weekdayName)")
                    }

                    Spacer()
                }
                .padding(.horizontal, BrandSpacing.md)
                .padding(.bottom, BrandSpacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: day.isOpen)
    }
}
