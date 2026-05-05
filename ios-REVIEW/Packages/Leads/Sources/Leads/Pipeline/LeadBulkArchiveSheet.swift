import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §9.2 Bulk archive won/lost leads

/// Sheet to bulk archive all leads in "converted" or "lost" states.
/// Presents a preview count, then fires parallel `PUT /leads/:id` calls.
@MainActor
@Observable
public final class LeadBulkArchiveViewModel {
    public enum Phase: Sendable { case idle, archiving, done(Int), failed(String) }

    public var selectedScope: BulkArchiveScope = .wonAndLost
    public private(set) var phase: Phase = .idle
    /// Preview count of affected leads.
    public private(set) var affectedCount: Int = 0
    public private(set) var isCountLoading = false

    @ObservationIgnored private let api: APIClient
    /// All pipeline leads supplied by the pipeline view.
    @ObservationIgnored private let allLeads: [Lead]

    public init(api: APIClient, allLeads: [Lead]) {
        self.api = api
        self.allLeads = allLeads
    }

    public func computePreview() {
        affectedCount = filtered(allLeads, scope: selectedScope).count
    }

    public func archive() async {
        let targets = filtered(allLeads, scope: selectedScope)
        guard !targets.isEmpty else { phase = .done(0); return }

        phase = .archiving

        var succeeded = 0
        await withTaskGroup(of: Bool.self) { group in
            for lead in targets {
                group.addTask {
                    do {
                        _ = try await self.api.updateLead(
                            id: lead.id,
                            body: LeadUpdateBody(status: "archived")
                        )
                        return true
                    } catch {
                        AppLog.ui.error("Bulk archive lead \(lead.id) failed: \(error.localizedDescription, privacy: .public)")
                        return false
                    }
                }
            }
            for await ok in group { if ok { succeeded += 1 } }
        }

        if succeeded == targets.count {
            phase = .done(succeeded)
        } else if succeeded == 0 {
            phase = .failed("Archive failed — check your connection and try again.")
        } else {
            phase = .done(succeeded) // partial success accepted
        }
    }

    private func filtered(_ leads: [Lead], scope: BulkArchiveScope) -> [Lead] {
        switch scope {
        case .wonOnly:    return leads.filter { $0.status == "converted" }
        case .lostOnly:   return leads.filter { $0.status == "lost" }
        case .wonAndLost: return leads.filter { $0.status == "converted" || $0.status == "lost" }
        }
    }
}

public enum BulkArchiveScope: String, CaseIterable, Sendable {
    case wonOnly    = "Won (Converted)"
    case lostOnly   = "Lost"
    case wonAndLost = "Won & Lost"
}

// MARK: - View

#if canImport(UIKit)

public struct LeadBulkArchiveSheet: View {
    @State private var vm: LeadBulkArchiveViewModel
    @Environment(\.dismiss) private var dismiss
    let onComplete: () -> Void

    public init(api: APIClient, allLeads: [Lead], onComplete: @escaping () -> Void) {
        _vm = State(wrappedValue: LeadBulkArchiveViewModel(api: api, allLeads: allLeads))
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)

                    Text("Bulk Archive Leads")
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)

                    // Scope picker
                    Picker("Scope", selection: $vm.selectedScope) {
                        ForEach(BulkArchiveScope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.selectedScope) { _, _ in vm.computePreview() }
                    .accessibilityLabel("Archive scope selector")

                    // Preview count
                    switch vm.phase {
                    case .idle, .archiving:
                        Text("Will archive \(vm.affectedCount) lead\(vm.affectedCount == 1 ? "" : "s")")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityLabel("Will archive \(vm.affectedCount) leads")
                    case .done(let count):
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.bizarreSuccess)
                            Text("Archived \(count) lead\(count == 1 ? "" : "s")")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreSuccess)
                        }
                    case .failed(let msg):
                        Text(msg)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 0)

                    // CTA
                    switch vm.phase {
                    case .idle:
                        Button {
                            Task { await vm.archive() }
                        } label: {
                            Text(vm.affectedCount == 0 ? "Nothing to Archive" : "Archive \(vm.affectedCount) Lead\(vm.affectedCount == 1 ? "" : "s")")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreOrange)
                        .disabled(vm.affectedCount == 0)
                        .accessibilityLabel("Archive selected leads")

                    case .archiving:
                        ProgressView("Archiving…")
                            .frame(maxWidth: .infinity, minHeight: 44)

                    case .done:
                        Button {
                            onComplete()
                            dismiss()
                        } label: {
                            Text("Done")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreOrange)

                    case .failed:
                        Button {
                            Task { await vm.archive() }
                        } label: {
                            Text("Retry")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreError)
                    }
                }
                .padding(BrandSpacing.lg)
            }
            .navigationTitle("Bulk Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel bulk archive")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task { vm.computePreview() }
    }
}
#endif
