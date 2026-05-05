#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §22.1 — iPad Inspector pane.
//
// Uses the `.inspector(isPresented:)` modifier (iOS 17+) to render a
// right-side editor panel alongside the Ticket detail content.
// Only shown on iPad (non-compact horizontal size class).
//
// Fields:
//   - Status picker    (uses available statuses fetched on appear)
//   - Assignee button  (navigates to AssigneePickerView sheet)
//   - Priority picker  (low / normal / high / critical — local until server field lands)
//   - Tags text field  (comma-separated — local until server field lands)

public struct TicketInspectorView: View {
    @Bindable var vm: TicketInspectorViewModel
    @State private var showingAssigneePicker: Bool = false
    private let api: any APIClient

    public init(vm: TicketInspectorViewModel, api: any APIClient) {
        self.vm = vm
        self.api = api
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                headerRow
                statusSection
                assigneeSection
                prioritySection
                tagsSection

                if let errorMessage = vm.errorMessage {
                    Text(errorMessage)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .padding(.horizontal, BrandSpacing.base)
                        .accessibilityLabel("Error: \(errorMessage)")
                }

                actionButtons
            }
            .padding(.vertical, BrandSpacing.base)
        }
        .background(Color.bizarreSurface1.ignoresSafeArea())
        .task { await vm.loadStatuses() }
        .sheet(isPresented: $showingAssigneePicker) {
            AssigneePickerView(
                api: api,
                currentAssigneeId: vm.assigneeId
            ) { employee in
                vm.assigneeId = employee?.id
                vm.assigneeName = employee?.displayName ?? ""
            }
        }
    }

    // MARK: — Header

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Inspector")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(vm.ticket.orderId)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
            Spacer()
            if vm.isSaving {
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityLabel("Saving")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: — Status

    private var statusSection: some View {
        InspectorSection(title: "Status") {
            if vm.isLoadingStatuses {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading statuses…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Loading status options")
            } else if vm.availableStatuses.isEmpty {
                // Fallback: show current status name when list failed to load
                Text(vm.selectedStatusName.isEmpty ? "—" : vm.selectedStatusName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            } else {
                Picker("Status", selection: Binding(
                    get: { vm.selectedStatusId ?? -1 },
                    set: { newId in
                        vm.selectedStatusId = newId == -1 ? nil : newId
                        vm.selectedStatusName = vm.availableStatuses
                            .first(where: { $0.id == newId })?.name ?? ""
                    }
                )) {
                    ForEach(vm.availableStatuses) { status in
                        Text(status.name).tag(status.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Ticket status picker")
            }
        }
    }

    // MARK: — Assignee

    private var assigneeSection: some View {
        InspectorSection(title: "Assignee") {
            Button {
                showingAssigneePicker = true
            } label: {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(vm.assigneeId != nil ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(vm.assigneeName.isEmpty ? "Unassigned" : vm.assigneeName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(vm.assigneeName.isEmpty ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel(
                vm.assigneeName.isEmpty
                    ? "Unassigned — tap to assign"
                    : "Assigned to \(vm.assigneeName) — tap to change"
            )
            .accessibilityHint("Opens employee picker")
        }
    }

    // MARK: — Priority

    private var prioritySection: some View {
        InspectorSection(title: "Priority") {
            Picker("Priority", selection: $vm.priority) {
                Text("—").tag("")
                Text("Low").tag("low")
                Text("Normal").tag("normal")
                Text("High").tag("high")
                Text("Critical").tag("critical")
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Priority picker")
        }
    }

    // MARK: — Tags

    private var tagsSection: some View {
        InspectorSection(title: "Tags") {
            TextField("Comma-separated tags", text: $vm.tagsText)
                .font(.brandBodyMedium())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Tags field — comma-separated")
        }
    }

    // MARK: — Actions

    private var actionButtons: some View {
        HStack(spacing: BrandSpacing.sm) {
            Button("Cancel") {
                vm.cancel()
            }
            .buttonStyle(.plain)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
            .accessibilityLabel("Cancel inspector changes")

            Button(vm.isSaving ? "Saving…" : "Save") {
                Task { await vm.save() }
            }
            .buttonStyle(.plain)
            .font(.brandBodyMedium()).bold()
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 10))
            .disabled(vm.isSaving)
            .accessibilityLabel(vm.isSaving ? "Saving" : "Save inspector changes")
        }
        .padding(.horizontal, BrandSpacing.base)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

// MARK: - InspectorSection helper

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.base)

            content()
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, BrandSpacing.base)
        }
        .accessibilityElement(children: .contain)
    }
}
#endif
