import SwiftUI
import DesignSystem

// MARK: - ScheduledReportsViewModel

@Observable
@MainActor
final class ScheduledReportsViewModel {
    var schedules: [ScheduledReport] = []
    var isLoading = false
    var errorMessage: String?
    var showAddSheet = false

    // New schedule form
    var newReportType = "revenue"
    var newFrequency: ScheduleFrequency = .weekly
    var newEmails = ""

    private let repository: ReportsRepository

    init(repository: ReportsRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            schedules = try await repository.getScheduledReports()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addSchedule() async {
        guard !newEmails.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let emails = newEmails.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        do {
            let created = try await repository.createScheduledReport(
                reportType: newReportType,
                frequency: newFrequency.rawValue,
                emails: emails
            )
            schedules.append(created)
            showAddSheet = false
            newEmails = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(id: Int64) async {
        do {
            try await repository.deleteScheduledReport(id: id)
            schedules.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ScheduledReportsSettingsView

public struct ScheduledReportsSettingsView: View {
    private let repository: ReportsRepository
    @State private var vm: ScheduledReportsViewModel

    public init(repository: ReportsRepository) {
        self.repository = repository
        _vm = State(wrappedValue: ScheduledReportsViewModel(repository: repository))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            listContent
        }
        .navigationTitle("Scheduled Reports")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add scheduled report")
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showAddSheet) {
            addSheet
        }
        .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading {
            ProgressView("Loading…")
                .accessibilityLabel("Loading scheduled reports")
        } else if vm.schedules.isEmpty {
            ContentUnavailableView {
                Label("No Scheduled Reports", systemImage: "clock.badge.checkmark")
            } description: {
                Text("Automatically receive reports by email on a daily, weekly, or monthly cadence.")
            } actions: {
                Button {
                    vm.showAddSheet = true
                } label: {
                    Label("Schedule a Report", systemImage: "plus.circle.fill")
                        .font(.brandLabelLarge())
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Schedule a new recurring report")
            }
        } else {
            List {
                ForEach(vm.schedules) { schedule in
                    scheduleRow(schedule)
                }
                .onDelete { offsets in
                    let ids = offsets.map { vm.schedules[$0].id }
                    Task { for id in ids { await vm.delete(id: id) } }
                }
            }
            .listStyle(.plain)
        }
    }

    private func scheduleRow(_ s: ScheduledReport) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Text(s.reportType.capitalized)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                StatusPill(s.frequency.rawValue.capitalized,
                           hue: s.isActive ? .ready : .archived)
            }
            Text(s.recipientEmails.joined(separator: ", "))
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
            if let next = s.nextRunAt {
                Text("Next: \(next)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(s.reportType.capitalized) report, \(s.frequency.rawValue), recipients: \(s.recipientEmails.joined(separator: ", ")).")
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Report Type") {
                    Picker("Type", selection: $vm.newReportType) {
                        Text("Revenue").tag("revenue")
                        Text("Tickets").tag("tickets")
                        Text("Employees").tag("employees")
                        Text("Inventory").tag("inventory")
                        Text("CSAT").tag("csat")
                        Text("NPS").tag("nps")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Select report type")
                }

                Section("Frequency") {
                    Picker("Frequency", selection: $vm.newFrequency) {
                        ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Select frequency")
                }

                Section("Recipient Emails") {
                    TextField("email1@example.com, email2@example.com",
                              text: $vm.newEmails, axis: .vertical)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Recipient emails, comma separated")
                }
            }
            .navigationTitle("New Scheduled Report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await vm.addSchedule() }
                    }
                    .disabled(vm.newEmails.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
