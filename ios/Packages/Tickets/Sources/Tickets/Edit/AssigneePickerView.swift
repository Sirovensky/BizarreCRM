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

public struct AssigneePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AssigneePickerViewModel
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

    private var employeeList: some View {
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

    private func employeeRow(_ employee: Employee) -> some View {
        let isCurrent = employee.id == currentAssigneeId
        return Button {
            onPick(employee)
            dismiss()
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
