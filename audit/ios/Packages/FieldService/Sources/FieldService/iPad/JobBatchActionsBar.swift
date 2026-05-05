// §22 JobBatchActionsBar — bulk-reassign toolbar shown when multi-select is active.
//
// Appears as a safeAreaInset bar at the bottom of the job list column when
// `vm.selectedJobIds` is non-empty.
//
// Actions:
//   - Reassign to tech (picker sheet)
//   - Clear selection
//
// Visual: glass capsule bar with count badge, reassign CTA, cancel button.
// Liquid Glass chrome: bar itself is branded glass. Content rows are not.
// A11y: fully labeled; count announced as live region update.

import SwiftUI
import DesignSystem

// MARK: - JobBatchActionsBar

struct JobBatchActionsBar: View {

    @Bindable var vm: DispatcherConsoleViewModel
    @State private var showReassignSheet = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Count badge
            Text("\(vm.selectedJobIds.count) selected")
                .font(.brandLabelLarge())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.updatesFrequently)

            Spacer()

            Button {
                showReassignSheet = true
            } label: {
                Label("Reassign", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.brandLabelLarge())
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(vm.batchState == .inProgress)
            .accessibilityLabel("Reassign \(vm.selectedJobIds.count) selected jobs")

            Button {
                vm.clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Clear selection")
            .frame(minWidth: DesignTokens.Touch.minTargetSide, minHeight: DesignTokens.Touch.minTargetSide)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .shadow(radius: DesignTokens.Shadows.md.blur, y: DesignTokens.Shadows.md.y)
        .overlay(batchStateOverlay)
        .sheet(isPresented: $showReassignSheet) {
            ReassignSheet(vm: vm, isPresented: $showReassignSheet)
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.snappy), value: vm.selectedJobIds.count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Batch actions toolbar")
    }

    @ViewBuilder
    private var batchStateOverlay: some View {
        switch vm.batchState {
        case .inProgress:
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Reassigning…")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        case .succeeded:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreSuccess)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        default:
            EmptyView()
        }
    }
}

// MARK: - ReassignSheet

private struct ReassignSheet: View {

    @Bindable var vm: DispatcherConsoleViewModel
    @Binding var isPresented: Bool
    @State private var selectedTechId: Int64? = nil

    private var rosterEntries: [TechRosterEntry] {
        if case .loaded(let entries) = vm.rosterState { return entries }
        return []
    }

    var body: some View {
        NavigationStack {
            List(rosterEntries) { entry in
                Button {
                    selectedTechId = entry.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text(entry.tech.displayName)
                                .font(.brandTitleSmall())
                                .foregroundStyle(.primary)
                            Text(entry.currentStatus.displayLabel)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedTechId == entry.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .frame(minHeight: DesignTokens.Touch.minTargetSide)
                }
                .hoverEffect(.highlight)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(entry.tech.displayName + ", " + entry.currentStatus.displayLabel)
                .accessibilityAddTraits(selectedTechId == entry.id ? .isSelected : [])
            }
            .listStyle(.sidebar)
            .navigationTitle("Reassign \(vm.selectedJobIds.count) Job\(vm.selectedJobIds.count == 1 ? "" : "s")")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reassign") {
                        guard let techId = selectedTechId else { return }
                        Task {
                            await vm.batchReassign(toTechnicianId: techId)
                            isPresented = false
                        }
                    }
                    .disabled(selectedTechId == nil)
                    .tint(.bizarreOrange)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
