import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - GoalEditorViewModel

@MainActor
@Observable
public final class GoalEditorViewModel {
    public var goalType: GoalType = .dailyRevenue
    public var targetValue: Double = 0
    public var period: GoalPeriod = .daily
    public var startDate: Date = Date()
    public var endDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    public var label: String = ""
    public var userId: String?
    public var teamId: String?

    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repo: any GoalsRepository
    @ObservationIgnored private let onSaved: @MainActor (Goal) -> Void

    public init(repo: any GoalsRepository, onSaved: @escaping @MainActor (Goal) -> Void) {
        self.repo = repo
        self.onSaved = onSaved
    }

    public func save() async {
        guard targetValue > 0 else {
            errorMessage = "Target value must be greater than zero."
            return
        }
        guard endDate > startDate else {
            errorMessage = "End date must be after start date."
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let req = CreateGoalRequest(
                userId: userId,
                teamId: teamId,
                goalType: goalType,
                targetValue: targetValue,
                period: period,
                startDate: startDate,
                endDate: endDate,
                label: label.isEmpty ? nil : label
            )
            let created = try await repo.createGoal(req)
            onSaved(created)
        } catch {
            AppLog.ui.error("GoalEditor save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - GoalEditorSheet

public struct GoalEditorSheet: View {
    @State private var vm: GoalEditorViewModel
    @Environment(\.dismiss) private var dismiss

    public init(repo: any GoalsRepository, onSaved: @escaping @MainActor (Goal) -> Void) {
        _vm = State(wrappedValue: GoalEditorViewModel(repo: repo, onSaved: onSaved))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    Picker("Type", selection: $vm.goalType) {
                        ForEach(GoalType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Picker("Period", selection: $vm.period) {
                        ForEach(GoalPeriod.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    LabeledContent("Target") {
                        TextField("0", value: $vm.targetValue, format: .number)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Label (optional)", text: $vm.label)
                }

                Section("Date Range") {
                    DatePicker("Start", selection: $vm.startDate, displayedComponents: .date)
                    DatePicker("End", selection: $vm.endDate,
                               in: vm.startDate...,
                               displayedComponents: .date)
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Goal")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await vm.save() }
                        }
                        .keyboardShortcut(.return)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Display name helpers

extension GoalType {
    var displayName: String {
        switch self {
        case .dailyRevenue:       return "Daily Revenue"
        case .weeklyTicketCount:  return "Weekly Tickets"
        case .monthlyAvgTicket:   return "Monthly Avg Ticket"
        case .personalCommission: return "Commission"
        case .custom:             return "Custom"
        }
    }
}

extension GoalPeriod {
    var displayName: String {
        switch self {
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}
