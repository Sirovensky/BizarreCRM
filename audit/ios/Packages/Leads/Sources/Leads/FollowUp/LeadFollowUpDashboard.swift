import SwiftUI
import Networking
import DesignSystem
import Core

// MARK: - LeadFollowUpDashboardViewModel

@MainActor
@Observable
public final class LeadFollowUpDashboardViewModel {

    public enum State: Sendable {
        case loading, loaded([LeadFollowUpReminder]), failed(String)
    }

    public private(set) var state: State = .loading

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        state = .loading
        do {
            let responses = try await api.todayFollowUps()
            let reminders: [LeadFollowUpReminder] = responses.compactMap { r in
                guard let date = ISO8601DateFormatter().date(from: r.dueAt) else { return nil }
                return LeadFollowUpReminder(
                    id: r.id,
                    leadId: r.leadId,
                    dueAt: date,
                    note: r.note,
                    completed: r.completed
                )
            }
            state = .loaded(reminders)
        } catch {
            AppLog.ui.error("Follow-up dashboard load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - LeadFollowUpDashboard

/// §9.6 — Today's due follow-ups, suitable for embedding in the Dashboard.
public struct LeadFollowUpDashboard: View {
    @State private var vm: LeadFollowUpDashboardViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: LeadFollowUpDashboardViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            switch vm.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .padding()
                    .frame(maxWidth: .infinity)
            case .loaded(let reminders):
                if reminders.isEmpty {
                    emptyView
                } else {
                    remindersList(reminders)
                }
            }
        }
        .navigationTitle("Today's Follow-Ups")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No follow-ups due today")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func remindersList(_ reminders: [LeadFollowUpReminder]) -> some View {
        List {
            ForEach(reminders) { reminder in
                ReminderRow(reminder: reminder)
                    .listRowBackground(Color.bizarreSurface1)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - ReminderRow

private struct ReminderRow: View {
    let reminder: LeadFollowUpReminder

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: reminder.isOverdue ? "exclamationmark.circle.fill" : "bell.fill")
                .foregroundStyle(reminder.isOverdue ? .bizarreError : .bizarreOrange)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Lead #\(reminder.leadId)")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if !reminder.note.isEmpty {
                    Text(reminder.note)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            Text(reminder.dueDateLabel)
                .font(.brandLabelSmall())
                .foregroundStyle(reminder.isOverdue ? .bizarreError : .bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Follow-up for lead \(reminder.leadId). \(reminder.note). Due \(reminder.dueDateLabel).")
    }
}
