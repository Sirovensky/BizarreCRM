#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4 — Assignee picker sheet.
//
// iPhone: standard bottom sheet (presentationDetents).
// iPad: same sheet but detents are .large so the employee list gets room.
//
// Liquid Glass rule: glass on the navigation bar only, never on list rows.

// MARK: - Recent technician store

/// Persists up to 5 recently assigned technician IDs in UserDefaults.
/// Used by `AssigneePickerView` to display a quick-access chip row.
enum RecentTechStore {
    private static let key = "com.bizarrecrm.recentAssigneeIds"
    private static let maxCount = 5

    static func load() -> [Int64] {
        (UserDefaults.standard.array(forKey: key) as? [Int64]) ?? []
    }

    /// Prepend `id` to the recents list, deduplicating and capping at `maxCount`.
    static func record(_ id: Int64) {
        var ids = load().filter { $0 != id }
        ids.insert(id, at: 0)
        if ids.count > maxCount { ids = Array(ids.prefix(maxCount)) }
        UserDefaults.standard.set(ids, forKey: key)
    }
}

// MARK: - AssigneePickerView

public struct AssigneePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AssigneePickerViewModel
    @State private var recentIds: [Int64] = RecentTechStore.load()
    private let currentAssigneeId: Int64?
    private let onPick: (Employee?) -> Void

    /// - Parameters:
    ///   - api: Live APIClient injected by the parent.
    ///   - currentAssigneeId: Pre-selected employee id (nil = unassigned).
    ///   - onPick: Called with the selected `Employee`, or `nil` for "Unassign".
    public init(
        api: APIClient,
        currentAssigneeId: Int64?,
        onPick: @escaping (Employee?) -> Void
    ) {
        self.currentAssigneeId = currentAssigneeId
        self.onPick = onPick
        _vm = State(wrappedValue: AssigneePickerViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Assign Technician")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search employees")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if currentAssigneeId != nil {
                        Button("Unassign") {
                            onPick(nil)
                            dismiss()
                        }
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Remove current assignee")
                    }
                }
            }
            .task { await vm.load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading employees")
        } else if let err = vm.errorMessage {
            errorView(err)
        } else if vm.filtered.isEmpty {
            emptyView
        } else {
            employeeList
        }
    }

    // MARK: - Recent technician chip row

    /// Horizontal chip strip of the most recently assigned technicians.
    /// Only shown when there are recent IDs whose employee records are loaded.
    @ViewBuilder
    private var recentTechChipRow: some View {
        let recents = recentIds.compactMap { id in vm.employees.first { $0.id == id } }
        if !recents.isEmpty && vm.searchText.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("RECENT")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.base)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(recents) { employee in
                            let isCurrent = employee.id == currentAssigneeId
                            Button {
                                pick(employee)
                            } label: {
                                HStack(spacing: BrandSpacing.xs) {
                                    ZStack {
                                        Circle()
                                            .fill(isCurrent ? Color.bizarreOrange : Color.bizarreSurface1)
                                            .frame(width: 26, height: 26)
                                        Text(employee.initials)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(isCurrent ? .black : .bizarreOnSurface)
                                    }
                                    .accessibilityHidden(true)
                                    Text(employee.displayName)
                                        .font(.brandLabelLarge())
                                        .foregroundStyle(.bizarreOnSurface)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, BrandSpacing.sm)
                                .padding(.vertical, BrandSpacing.xs)
                                .background(
                                    isCurrent ? Color.bizarreOrange.opacity(0.15) : Color.bizarreSurface1,
                                    in: Capsule()
                                )
                                .overlay(Capsule().strokeBorder(
                                    isCurrent ? Color.bizarreOrange.opacity(0.5) : Color.bizarreOutline.opacity(0.4),
                                    lineWidth: isCurrent ? 1.5 : 0.5
                                ))
                            }
                            .buttonStyle(.plain)
                            .hoverEffect(.highlight)
                            .accessibilityLabel("\(employee.displayName)\(isCurrent ? ", currently assigned" : ""), recent technician")
                            .accessibilityHint("Assign this technician")
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.sm)
                }
                .scrollClipDisabled()
            }
            .padding(.top, BrandSpacing.sm)

            Divider().overlay(Color.bizarreOutline.opacity(0.2))
        }
    }

    private var employeeList: some View {
        VStack(spacing: 0) {
            recentTechChipRow

            List {
                ForEach(vm.filtered) { employee in
                    employeeRow(employee)
                        .listRowBackground(Color.bizarreSurface1)
                        .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Pick helper

    private func pick(_ employee: Employee) {
        RecentTechStore.record(employee.id)
        onPick(employee)
        dismiss()
    }

    private func employeeRow(_ employee: Employee) -> some View {
        let isCurrent = employee.id == currentAssigneeId
        return Button {
            pick(employee)
        } label: {
            HStack(spacing: BrandSpacing.md) {
                // Avatar circle with initials
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.bizarreOrange : Color.bizarreSurface1)
                        .frame(width: 36, height: 36)
                    Text(employee.initials)
                        .font(.brandLabelLarge())
                        .foregroundStyle(isCurrent ? .black : .bizarreOnSurface)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(employee.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let email = employee.email, !email.isEmpty {
                        Text(email)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Currently assigned")
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(employee.displayName)\(isCurrent ? ", currently assigned" : "")")
        .accessibilityHint("Assign this technician to the ticket")
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(vm.searchText.isEmpty ? "No active employees." : "No results for \"\(vm.searchText)\".")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load employees")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.lg)
    }
}
#endif
