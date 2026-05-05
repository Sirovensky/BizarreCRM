#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.6 — @mention trigger for note compose.
//
// When the user types "@" in the note content field, this picker appears
// as a popover (iPad) or compact list (iPhone) with matching employees.
// Selecting a name inserts "@{firstName}" token at the insertion point.
//
// The picker calls GET /employees and filters locally by the query
// following the "@" trigger.

// MARK: - MentionCandidate

public struct MentionCandidate: Identifiable, Sendable, Hashable {
    public let id: Int64
    public let firstName: String
    public let lastName: String
    public let role: String?

    public var displayName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
    public var mentionToken: String { "@\(firstName)" }
}

// MARK: - TicketNoteMentionPickerViewModel

@MainActor
@Observable
public final class TicketNoteMentionPickerViewModel {
    public var query: String = ""
    public private(set) var candidates: [MentionCandidate] = []
    public private(set) var allEmployees: [MentionCandidate] = []
    public private(set) var isLoading: Bool = false

    public var filteredCandidates: [MentionCandidate] {
        let q = query.lowercased()
        guard !q.isEmpty else { return allEmployees }
        return allEmployees.filter {
            $0.firstName.lowercased().hasPrefix(q) || $0.lastName.lowercased().hasPrefix(q)
        }
    }

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        guard allEmployees.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let employees = try await api.ticketAssigneeCandidates()
            allEmployees = employees.map {
                MentionCandidate(
                    id: $0.id,
                    firstName: $0.firstName ?? "",
                    lastName: $0.lastName ?? "",
                    role: $0.role
                )
            }
        } catch {
            AppLog.ui.error("Mention picker load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - TicketNoteMentionPicker

public struct TicketNoteMentionPicker: View {
    @State private var vm: TicketNoteMentionPickerViewModel
    let query: String
    let onSelect: (MentionCandidate) -> Void
    let onDismiss: () -> Void

    public init(
        api: APIClient,
        query: String,
        onSelect: @escaping (MentionCandidate) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.query = query
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        _vm = State(wrappedValue: TicketNoteMentionPickerViewModel(api: api))
    }

    public var body: some View {
        Group {
            if vm.isLoading {
                HStack(spacing: BrandSpacing.xs) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading…")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(BrandSpacing.sm)
            } else if vm.filteredCandidates.isEmpty {
                Text("No matching team members")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(BrandSpacing.sm)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.filteredCandidates) { candidate in
                            Button {
                                onSelect(candidate)
                            } label: {
                                HStack(spacing: BrandSpacing.sm) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(candidate.displayName)
                                            .font(.brandBodyMedium())
                                            .foregroundStyle(.bizarreOnSurface)
                                        if let role = candidate.role {
                                            Text(role.capitalized)
                                                .font(.brandLabelSmall())
                                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, BrandSpacing.base)
                                .padding(.vertical, BrandSpacing.xs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .accessibilityLabel("Mention \(candidate.displayName)")
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color.bizarreSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.4)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .onChange(of: query) { _, new in vm.query = new }
        .task {
            vm.query = query
            await vm.load()
        }
    }
}
#endif
