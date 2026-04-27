import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - RecognitionShoutout
//
// §46.7 — Peer-to-peer shoutouts.
// Model + CRUD views.
// Server routes (§74 gap — mark as needed):
//   POST /api/v1/recognition/shoutouts  { to_employee_id, category, message, ticket_id? }
//   GET  /api/v1/recognition/shoutouts?employee_id=X  → list for profile
//   GET  /api/v1/recognition/shoutouts/team  → all recent (for team chat feed)
//
// Privacy: private by default; recipient can opt-in to team-visible.

public enum ShoutoutCategory: String, CaseIterable, Codable, Sendable {
    case customerSave     = "customer_save"
    case teamPlayer       = "team_player"
    case technicalExcellence = "technical_excellence"
    case aboveAndBeyond   = "above_and_beyond"

    public var displayName: String {
        switch self {
        case .customerSave:         return "Customer Save"
        case .teamPlayer:           return "Team Player"
        case .technicalExcellence:  return "Technical Excellence"
        case .aboveAndBeyond:       return "Above & Beyond"
        }
    }

    public var icon: String {
        switch self {
        case .customerSave:         return "star.fill"
        case .teamPlayer:           return "person.2.fill"
        case .technicalExcellence:  return "gearshape.2.fill"
        case .aboveAndBeyond:       return "arrow.up.circle.fill"
        }
    }
}

public struct RecognitionShoutout: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let fromEmployeeId: String
    public let toEmployeeId: String
    public let category: ShoutoutCategory
    public let message: String
    public let ticketId: Int64?
    public let isTeamVisible: Bool
    public let createdAt: Date

    // Joined display fields (from server JOIN):
    public let fromDisplayName: String?
    public let toDisplayName: String?

    public init(
        id: String = UUID().uuidString,
        fromEmployeeId: String,
        toEmployeeId: String,
        category: ShoutoutCategory,
        message: String,
        ticketId: Int64? = nil,
        isTeamVisible: Bool = false,
        createdAt: Date = Date(),
        fromDisplayName: String? = nil,
        toDisplayName: String? = nil
    ) {
        self.id = id
        self.fromEmployeeId = fromEmployeeId
        self.toEmployeeId = toEmployeeId
        self.category = category
        self.message = message
        self.ticketId = ticketId
        self.isTeamVisible = isTeamVisible
        self.createdAt = createdAt
        self.fromDisplayName = fromDisplayName
        self.toDisplayName = toDisplayName
    }

    enum CodingKeys: String, CodingKey {
        case id, category, message
        case fromEmployeeId  = "from_employee_id"
        case toEmployeeId    = "to_employee_id"
        case ticketId        = "ticket_id"
        case isTeamVisible   = "is_team_visible"
        case createdAt       = "created_at"
        case fromDisplayName = "from_display_name"
        case toDisplayName   = "to_display_name"
    }
}

// MARK: - SendShoutoutViewModel

@MainActor
@Observable
public final class SendShoutoutViewModel {
    public var toEmployeeId: String = ""
    public var category: ShoutoutCategory = .aboveAndBeyond
    public var message: String = ""
    public var ticketId: Int64? = nil
    public var isTeamVisible: Bool = false

    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var sent: RecognitionShoutout?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let fromEmployeeId: String

    public init(api: APIClient, fromEmployeeId: String) {
        self.api = api
        self.fromEmployeeId = fromEmployeeId
    }

    public var isValid: Bool {
        !toEmployeeId.isEmpty && !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func send() async {
        guard isValid else {
            errorMessage = "Please select a recipient and write a message."
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            sent = try await api.sendShoutout(
                fromEmployeeId: fromEmployeeId,
                toEmployeeId: toEmployeeId,
                category: category,
                message: message,
                ticketId: ticketId,
                isTeamVisible: isTeamVisible
            )
        } catch {
            AppLog.ui.error("Shoutout send failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - SendShoutoutSheet

public struct SendShoutoutSheet: View {
    @State private var vm: SendShoutoutViewModel
    @Environment(\.dismiss) private var dismiss

    public let colleagues: [Employee]
    public let onSent: (RecognitionShoutout) -> Void

    public init(
        api: APIClient,
        fromEmployeeId: String,
        colleagues: [Employee],
        onSent: @escaping (RecognitionShoutout) -> Void
    ) {
        self.colleagues = colleagues
        self.onSent = onSent
        _vm = State(wrappedValue: SendShoutoutViewModel(api: api, fromEmployeeId: fromEmployeeId))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    Picker("To", selection: $vm.toEmployeeId) {
                        Text("Select colleague").tag("")
                        ForEach(colleagues, id: \.id) { emp in
                            Text(emp.displayName).tag("\(emp.id)")
                        }
                    }
                    .accessibilityLabel("Select recipient")
                }

                Section("Category") {
                    Picker("Category", selection: $vm.category) {
                        ForEach(ShoutoutCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityLabel("Select shoutout category")
                }

                Section("Message") {
                    TextField("What did they do?", text: $vm.message, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityLabel("Shoutout message")
                }

                Section {
                    Toggle("Share with team", isOn: $vm.isTeamVisible)
                        .accessibilityLabel("Make this shoutout visible to the whole team")
                } footer: {
                    Text("By default only you and the recipient see this. Toggle to share with the team.")
                        .font(.brandLabelSmall())
                }

                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.bizarreError) }
                }

                if let shoutout = vm.sent {
                    Section {
                        Label("Shoutout sent!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    onSent(shoutout)
                                    dismiss()
                                }
                            }
                    }
                }
            }
            .navigationTitle("Send Shoutout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await vm.send() }
                    }
                    .disabled(!vm.isValid || vm.isSaving)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .accessibilityLabel("Send shoutout")
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - ShoutoutsListView (employee profile tab)

@MainActor
@Observable
public final class ShoutoutsListViewModel {
    public private(set) var shoutouts: [RecognitionShoutout] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let employeeId: String

    public init(api: APIClient, employeeId: String) {
        self.api = api
        self.employeeId = employeeId
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            shoutouts = try await api.listShoutouts(employeeId: employeeId)
        } catch {
            AppLog.ui.error("Shoutouts load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct ShoutoutsListView: View {
    @State private var vm: ShoutoutsListViewModel
    @State private var showSendSheet = false
    private let api: APIClient
    private let currentEmployeeId: String
    private let colleagues: [Employee]

    public init(api: APIClient, employeeId: String, currentEmployeeId: String, colleagues: [Employee]) {
        self.api = api
        self.currentEmployeeId = currentEmployeeId
        self.colleagues = colleagues
        _vm = State(wrappedValue: ShoutoutsListViewModel(api: api, employeeId: employeeId))
    }

    public var body: some View {
        Group {
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.shoutouts.isEmpty {
                ContentUnavailableView(
                    "No Shoutouts Yet",
                    systemImage: "hands.clap",
                    description: Text("Recognize a teammate for great work!")
                )
            } else {
                List(vm.shoutouts) { s in
                    ShoutoutRow(shoutout: s)
                        .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Shoutouts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSendSheet = true
                } label: {
                    Image(systemName: "hands.clap")
                }
                .accessibilityLabel("Send shoutout to a colleague")
                .keyboardShortcut("n", modifiers: .command)
            }
            // §46.7 Recognition book — end-of-year PDF export
            if !vm.shoutouts.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        RecognitionBookButton(
                            shoutouts: vm.shoutouts,
                            employeeName: vm.shoutouts.first?.toDisplayName ?? "Employee"
                        )
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showSendSheet) {
            SendShoutoutSheet(
                api: api,
                fromEmployeeId: currentEmployeeId,
                colleagues: colleagues
            ) { _ in
                showSendSheet = false
                Task { await vm.load() }
            }
        }
    }
}

// MARK: - ShoutoutRow

private struct ShoutoutRow: View {
    let shoutout: RecognitionShoutout

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: shoutout.category.icon)
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(shoutout.category.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
                Spacer()
                if let from = shoutout.fromDisplayName {
                    Text("from \(from)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Text(shoutout.message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(shoutout.category.displayName) from \(shoutout.fromDisplayName ?? "a colleague"): \(shoutout.message)"
        )
    }
}

// MARK: - APIClient extensions for shoutouts

public extension APIClient {
    func sendShoutout(
        fromEmployeeId: String,
        toEmployeeId: String,
        category: ShoutoutCategory,
        message: String,
        ticketId: Int64?,
        isTeamVisible: Bool
    ) async throws -> RecognitionShoutout {
        struct Body: Encodable, Sendable {
            let toEmployeeId: String
            let category: ShoutoutCategory
            let message: String
            let ticketId: Int64?
            let isTeamVisible: Bool
            enum CodingKeys: String, CodingKey {
                case category, message
                case toEmployeeId  = "to_employee_id"
                case ticketId      = "ticket_id"
                case isTeamVisible = "is_team_visible"
            }
        }
        return try await post(
            "/api/v1/recognition/shoutouts",
            body: Body(
                toEmployeeId: toEmployeeId,
                category: category,
                message: message,
                ticketId: ticketId,
                isTeamVisible: isTeamVisible
            ),
            as: RecognitionShoutout.self
        )
    }

    func listShoutouts(employeeId: String) async throws -> [RecognitionShoutout] {
        try await get(
            "/api/v1/recognition/shoutouts",
            query: [URLQueryItem(name: "employee_id", value: employeeId)],
            as: [RecognitionShoutout].self
        )
    }
}
