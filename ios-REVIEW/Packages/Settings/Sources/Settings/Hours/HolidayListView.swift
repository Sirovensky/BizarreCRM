import SwiftUI
import Core
import DesignSystem

// MARK: - §19 HolidayListView

/// Lists upcoming holiday exceptions (next 12 months) + add/edit/delete.
public struct HolidayListView: View {

    @State private var viewModel: HolidayListViewModel
    @State private var showAddSheet: Bool = false
    @State private var showPresetsSheet: Bool = false
    @State private var editingHoliday: HolidayException?

    public init(viewModel: HolidayListViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        List {
            if viewModel.upcoming.isEmpty {
                ContentUnavailableView(
                    "No holidays scheduled",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Add holidays or import US presets.")
                )
            } else {
                ForEach(viewModel.upcoming) { holiday in
                    HolidayRow(holiday: holiday)
                        .contentShape(Rectangle())
                        .onTapGesture { editingHoliday = holiday }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(id: holiday.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Edit") { editingHoliday = holiday }
                            Button("Delete", role: .destructive) {
                                Task { await viewModel.delete(id: holiday.id) }
                            }
                        }
                        #if canImport(UIKit)
                        .hoverEffect(.highlight)
                        #endif
                        .accessibilityLabel("\(holiday.reason): \(holiday.isOpen ? "Special hours" : "Closed"), \(holiday.date.formatted(date: .abbreviated, time: .omitted))")
                }
            }
        }
        .navigationTitle("Holidays & Exceptions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showPresetsSheet = true
                } label: {
                    Label("Import presets", systemImage: "sparkles")
                }
                .accessibilityLabel("Import US holiday presets")

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add holiday", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("Add holiday exception")
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showAddSheet) {
            HolidayEditorSheet(
                viewModel: HolidayEditorViewModel(mode: .create, repository: viewModel.repository),
                onDone: { await viewModel.load() }
            )
        }
        .sheet(item: $editingHoliday) { holiday in
            HolidayEditorSheet(
                viewModel: HolidayEditorViewModel(mode: .edit(holiday), repository: viewModel.repository),
                onDone: { await viewModel.load() }
            )
        }
        .sheet(isPresented: $showPresetsSheet) {
            HolidayPresetsSheet(repository: viewModel.repository, onDone: { await viewModel.load() })
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - HolidayRow

private struct HolidayRow: View {
    let holiday: HolidayException

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(holiday.reason)
                    .fontWeight(.medium)
                Text(Self.dateFormatter.string(from: holiday.date))
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                if holiday.recurring != .once {
                    Text("Repeats \(holiday.recurring.displayName.lowercased())")
                        .font(.caption2)
                        .foregroundStyle(.bizarreOrange)
                }
            }
            Spacer()
            Text(holiday.isOpen ? "Special hours" : "Closed")
                .font(.caption)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(
                    Capsule().fill(holiday.isOpen ? Color.bizarreTeal.opacity(0.15) : Color.bizarreError.opacity(0.15))
                )
                .foregroundStyle(holiday.isOpen ? Color.bizarreTeal : Color.bizarreError)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - HolidayListViewModel

@Observable
@MainActor
public final class HolidayListViewModel {

    public var holidays: [HolidayException] = []
    public var errorMessage: String?
    public let repository: any HoursRepository

    public init(repository: any HoursRepository) {
        self.repository = repository
    }

    /// Returns holidays in the next 12 months, sorted by date ascending.
    public var upcoming: [HolidayException] {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .month, value: 12, to: now) ?? now
        return holidays
            .filter { $0.date >= now && $0.date <= cutoff }
            .sorted { $0.date < $1.date }
    }

    public func load() async {
        do {
            holidays = try await repository.fetchHolidays()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func delete(id: String) async {
        do {
            try await repository.deleteHoliday(id: id)
            holidays.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
