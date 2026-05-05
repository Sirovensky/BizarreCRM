import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - GoalListViewModel

@MainActor
@Observable
public final class GoalListViewModel {
    public private(set) var goals: [Goal] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var showEditor: Bool = false

    @ObservationIgnored let repo: any GoalsRepository
    @ObservationIgnored private let userId: String?

    public init(repo: any GoalsRepository, userId: String? = nil) {
        self.repo = repo
        self.userId = userId
    }

    public func load() async {
        if goals.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            goals = try await repo.listGoals(userId: userId, teamId: nil)
        } catch {
            AppLog.ui.error("GoalList load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func delete(goal: Goal) async {
        let id = goal.id
        goals.removeAll { $0.id == id }
        do {
            try await repo.deleteGoal(id: id)
        } catch {
            AppLog.ui.error("GoalList delete failed: \(error.localizedDescription, privacy: .public)")
            await load()
        }
    }

    public func append(_ goal: Goal) {
        goals.append(goal)
    }
}

// MARK: - GoalListView

public struct GoalListView: View {
    @State private var vm: GoalListViewModel
    @State private var toastMilestone: Int = 50
    @State private var toastGoalLabel: String = ""
    @State private var showToast: Bool = false

    public init(repo: any GoalsRepository, userId: String? = nil) {
        _vm = State(wrappedValue: GoalListViewModel(repo: repo, userId: userId))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Group {
                if Platform.isCompact {
                    compactLayout
                } else {
                    regularLayout
                }
            }

            GoalMilestoneToast(
                milestone: toastMilestone,
                goalLabel: toastGoalLabel,
                isPresented: showToast
            )
            .padding(.top, DesignTokens.Spacing.xxl)
            .zIndex(DesignTokens.Z.toast)
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $vm.showEditor) {
            GoalEditorSheet(repo: vm.repo) { goal in
                vm.append(goal)
                vm.showEditor = false
            }
        }
    }

    // MARK: - Compact (iPhone)

    @ViewBuilder private var compactLayout: some View {
        NavigationStack {
            goalContent
                .navigationTitle("Goals")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            vm.showEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityLabel("Add goal")
                    }
                }
        }
    }

    // MARK: - Regular (iPad)

    @ViewBuilder private var regularLayout: some View {
        NavigationSplitView {
            goalContent
                .navigationTitle("Goals")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            vm.showEditor = true
                        } label: {
                            Label("New Goal", systemImage: "plus")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                    }
                }
        } detail: {
            Text("Select a goal")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared list

    @ViewBuilder private var goalContent: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.goals.isEmpty {
            ContentUnavailableView(
                "No Goals",
                systemImage: "target",
                description: Text("Add goals to track team performance.")
            )
        } else {
            List {
                ForEach(vm.goals) { goal in
                    goalRow(goal)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await vm.delete(goal: goal) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { idx in
                    let all = vm.goals
                    for i in idx { Task { await vm.delete(goal: all[i]) } }
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder private func goalRow(_ goal: Goal) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            GoalProgressRingView(
                fraction: goal.progressFraction,
                size: 48,
                label: "\(goal.goalType.displayName)"
            )
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(goal.label ?? goal.goalType.displayName)
                    .font(.headline)
                Text(goal.period.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.0f / %.0f", goal.currentValue, goal.targetValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(goal.label ?? goal.goalType.displayName), \(Int(goal.progressFraction * 100)) percent complete")
    }
}
