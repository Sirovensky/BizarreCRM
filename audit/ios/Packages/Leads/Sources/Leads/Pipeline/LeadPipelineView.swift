import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - LeadPipelineView

/// §9.2 — Kanban board for the Leads pipeline.
/// iPad/Mac: horizontal scroll showing all columns.
/// iPhone:   stage picker + single column at a time.
public struct LeadPipelineView: View {
    @State private var vm: LeadPipelineViewModel
    @State private var selectedStage: PipelineStage = .new
    @State private var archiveTarget: PipelineStage? = nil
    @State private var showingArchiveConfirm: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(api: APIClient) {
        _vm = State(wrappedValue: LeadPipelineViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            switch vm.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                errorView(msg)
            case .loaded:
                if Platform.isCompact {
                    iPhoneLayout
                } else {
                    iPadLayout
                }
            }
        }
        .navigationTitle("Pipeline")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar {
            // §9.2 Bulk archive won/lost
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    let wonCount = vm.leads(in: .won).count
                    let lostCount = vm.leads(in: .lost).count
                    Button {
                        archiveTarget = .won
                        showingArchiveConfirm = true
                    } label: {
                        Label(
                            "Archive Won (\(wonCount))",
                            systemImage: "archivebox"
                        )
                    }
                    .disabled(wonCount == 0)
                    .accessibilityLabel("Archive all \(wonCount) won leads")

                    Button(role: .destructive) {
                        archiveTarget = .lost
                        showingArchiveConfirm = true
                    } label: {
                        Label(
                            "Archive Lost (\(lostCount))",
                            systemImage: "archivebox"
                        )
                    }
                    .disabled(lostCount == 0)
                    .accessibilityLabel("Archive all \(lostCount) lost leads")
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .accessibilityLabel("Bulk archive won or lost leads")
            }
        }
        .confirmationDialog(
            archiveTarget == .won
                ? "Archive \(vm.leads(in: .won).count) Won lead\(vm.leads(in: .won).count == 1 ? "" : "s")?"
                : "Archive \(vm.leads(in: .lost).count) Lost lead\(vm.leads(in: .lost).count == 1 ? "" : "s")?",
            isPresented: $showingArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                if let target = archiveTarget {
                    Task { await vm.bulkArchive(stage: target) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move all leads from the \(archiveTarget?.displayName ?? "") column to Archived. This can be undone from the lead detail.")
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            // Stage picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(PipelineStage.allCases) { stage in
                        stagePill(stage, isSelected: stage == selectedStage)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
            }
            .brandGlass(.regular, in: Rectangle())

            // Single column
            currentColumnView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentColumnView: some View {
        ScrollView {
            LazyVStack(spacing: BrandSpacing.sm) {
                ForEach(vm.leads(in: selectedStage)) { lead in
                    LeadKanbanCard(lead: lead, stage: selectedStage, onMoveTo: handleMove)
                }
                if vm.leads(in: selectedStage).isEmpty {
                    Text("No leads in \(selectedStage.displayName)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, BrandSpacing.xxl)
                }
            }
            .padding(BrandSpacing.base)
        }
    }

    private func stagePill(_ stage: PipelineStage, isSelected: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(duration: 0.25)) {
                selectedStage = stage
            }
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Text(stage.displayName)
                    .font(.brandLabelLarge())
                Text("\(vm.leads(in: stage).count)")
                    .font(.brandMono(size: 11))
            }
            .foregroundStyle(isSelected ? .bizarreOnOrange : .bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            .background(isSelected ? Color.bizarreOrange : Color.bizarreSurface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.displayName), \(vm.leads(in: stage).count) leads\(isSelected ? ", selected" : "")")
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: BrandSpacing.base) {
                ForEach(PipelineStage.allCases) { stage in
                    LeadPipelineColumn(
                        stage: stage,
                        leads: vm.leads(in: stage),
                        totalValueCents: vm.totalValueCents(in: stage),
                        onMoveTo: handleMove
                    )
                    .dropDestination(for: String.self) { ids, _ in
                        handleDrop(ids: ids.compactMap { Int64($0) }, to: stage)
                        return true
                    }
                }
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load pipeline")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Handlers

    private func handleMove(lead: Lead, to stage: PipelineStage) {
        Task {
            await vm.moveCard(lead: lead, to: stage)
        }
    }

    private func handleDrop(ids: [Int64], to stage: PipelineStage) { // swiftlint:disable:next function_body_length
        for id in ids {
            // Find the lead in any column.
            for s in PipelineStage.allCases {
                if let lead = vm.leads(in: s).first(where: { $0.id == id }) {
                    handleMove(lead: lead, to: stage)
                    break
                }
            }
        }
    }
}
