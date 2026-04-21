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
