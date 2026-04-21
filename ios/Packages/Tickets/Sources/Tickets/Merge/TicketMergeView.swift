#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §4 — Ticket merge UI.
/// iPhone: sheet with sequential steps. iPad: 3-column NavigationSplitView.
@MainActor
public struct TicketMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @State var vm: TicketMergeViewModel
    @State private var showingCandidatePicker = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(vm: TicketMergeViewModel) {
        self._vm = State(wrappedValue: vm)
    }

    public var body: some View {
        Group {
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .task { await vm.loadPrimary() }
        .sheet(isPresented: $showingCandidatePicker) {
            TicketMergeCandidatePicker(vm: vm)
        }
        .onChange(of: vm.state) { _, new in
            if case .success = new { dismiss() }
        }
    }

    // MARK: - iPad 3-col

    private var iPadLayout: some View {
        NavigationSplitView {
            primaryColumn
        } content: {
            secondaryColumn
        } detail: {
            diffColumn
        }
        .navigationTitle("Merge Tickets")
    }

    // MARK: - iPhone sheet

    private var iPhoneLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        primaryColumn
                        Divider().overlay(Color.bizarreOutline.opacity(0.4))
                        secondaryColumn
                        if vm.primaryTicket != nil && vm.secondaryTicket != nil {
                            diffColumn
                        }
                        mergeButton
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle("Merge Tickets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Columns

    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Primary (keep)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if let t = vm.primaryTicket {
                ticketCard(t, badge: "PRIMARY")
            } else {
                loadingCard
            }
        }
        .padding(BrandSpacing.base)
    }

    private var secondaryColumn: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Duplicate (merge in)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if let t = vm.secondaryTicket {
                ticketCard(t, badge: "DUPLICATE")
            } else {
                Button {
                    showingCandidatePicker = true
                } label: {
                    Label("Pick duplicate ticket…", systemImage: "doc.on.doc")
                        .font(.brandBodyMedium())
                        .frame(maxWidth: .infinity)
                        .padding(BrandSpacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreTeal)
                .accessibilityLabel("Pick duplicate ticket to merge")
            }
        }
        .padding(BrandSpacing.base)
    }

    private var diffColumn: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Field preferences")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            ForEach($vm.preferences, id: \.field) { $pref in
                MergeFieldRow(preference: $pref)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Field \(pref.field), winner: \(pref.winner == .primary ? "primary" : "secondary")")
            }
            mergeButton
        }
        .padding(BrandSpacing.base)
    }

    // MARK: - Merge button

    private var mergeButton: some View {
        VStack(spacing: BrandSpacing.sm) {
            if case .failed(let msg) = vm.state {
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error: \(msg)")
            }
            Button {
                Task { await vm.merge() }
            } label: {
                Group {
                    if case .merging = vm.state {
                        ProgressView()
                    } else {
                        Label("Merge Tickets", systemImage: "arrow.triangle.merge")
                            .font(.brandBodyLarge())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreError)
            .disabled(vm.secondaryTicket == nil || { if case .merging = vm.state { return true }; return false }())
            .accessibilityLabel("Merge tickets — destructive action")
            .accessibilityHint("Merges the duplicate ticket into the primary. This cannot be undone.")

            Text("Merge is permanent. The duplicate ticket's notes and devices will be combined into the primary.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Cards

    private func ticketCard(_ ticket: TicketDetail, badge: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text(ticket.orderId)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Spacer()
                Text(badge)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(badge == "PRIMARY" ? Color.bizarreTeal : Color.bizarreOrange, in: Capsule())
                    .accessibilityLabel(badge == "PRIMARY" ? "Primary ticket" : "Duplicate ticket")
            }
            if let customer = ticket.customer {
                Text(customer.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let status = ticket.status {
                Text(status.name)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var loadingCard: some View {
        HStack {
            ProgressView()
            Text("Loading…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Field row

private struct MergeFieldRow: View {
    @Binding var preference: MergeFieldPreference

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Text(preference.field.capitalized)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Winner", selection: $preference.winner) {
                Text("Primary").tag(MergeFieldPreference.Winner.primary)
                Text("Secondary").tag(MergeFieldPreference.Winner.secondary)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
