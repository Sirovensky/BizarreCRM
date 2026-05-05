#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §4 — Search dialog for picking the secondary (duplicate) ticket to merge.
public struct TicketMergeCandidatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: TicketMergeViewModel

    public init(vm: TicketMergeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    results
                }
            }
            .navigationTitle("Pick Duplicate Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            TextField("Search by ID, customer, device…", text: $vm.candidateSearchQuery)
                .font(.brandBodyMedium())
                .accessibilityLabel("Search tickets")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top], BrandSpacing.base)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if vm.candidateResults.isEmpty && !vm.candidateSearchQuery.isEmpty {
            emptyState
        } else {
            List(vm.candidateResults) { ticket in
                CandidateRow(ticket: ticket) {
                    Task {
                        await vm.selectCandidate(ticket)
                        dismiss()
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Spacer()
            Image(systemName: "ticket.slash")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No matching tickets")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
        }
    }
}

// MARK: - Row

private struct CandidateRow: View {
    let ticket: TicketSummary
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(ticket.orderId)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let name = ticket.customer?.displayName, !name.isEmpty {
                        Text(name)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let device = ticket.firstDevice?.deviceName, !device.isEmpty {
                        Text(device)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ticket \(ticket.orderId)\(ticket.customer.map { ", \($0.displayName)" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}
#endif
