import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - WaitlistOfferFlowViewModel

@MainActor
@Observable
public final class WaitlistOfferFlowViewModel {
    public private(set) var rankedCandidates: [WaitlistEntry] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var offeredEntry: WaitlistEntry?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load(availableSlot: Date, duration: TimeInterval) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let all = try await api.listWaitlistEntries()
            rankedCandidates = WaitlistMatcher.rank(
                candidates: all,
                availableSlot: availableSlot,
                duration: duration
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func offer(entry: WaitlistEntry) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let updated = try await api.offerWaitlistEntry(id: entry.id)
            offeredEntry = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - WaitlistOfferFlowView

/// Presented when a slot opens. Shows ranked candidates → admin taps "Offer".
public struct WaitlistOfferFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: WaitlistOfferFlowViewModel

    private let availableSlot: Date
    private let duration: TimeInterval

    public init(api: APIClient, availableSlot: Date, duration: TimeInterval) {
        self.availableSlot = availableSlot
        self.duration = duration
        _vm = State(wrappedValue: WaitlistOfferFlowViewModel(api: api))
    }

    private static let slotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                contentView
            }
            .navigationTitle("Offer Open Slot")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await vm.load(availableSlot: availableSlot, duration: duration) }
        }
        .presentationBackground(.ultraThinMaterial)
        .alert("Slot Offered", isPresented: Binding(
            get: { vm.offeredEntry != nil },
            set: { if !$0 { vm.reset(); dismiss() } }
        )) {
            Button("Done") { vm.reset(); dismiss() }
        } message: {
            if let entry = vm.offeredEntry {
                Text("SMS sent to customer #\(entry.customerId).")
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            PhaseErrorView(message: err) {
                Task { await vm.load(availableSlot: availableSlot, duration: duration) }
            }
        } else if vm.rankedCandidates.isEmpty {
            PhaseEmptyView(icon: "person.crop.circle.badge.xmark", text: "No waitlist candidates")
        } else {
            List {
                Section {
                    slotHeader
                }
                Section("Ranked Candidates") {
                    ForEach(vm.rankedCandidates) { entry in
                        CandidateRow(entry: entry) {
                            Task { await vm.offer(entry: entry) }
                        }
                        .listRowBackground(Color.bizarreSurface1)
                        .brandHover()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var slotHeader: some View {
        HStack {
            Image(systemName: "calendar.badge.plus")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Open slot")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(Self.slotFormatter.string(from: availableSlot))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(String(format: "%.0f min", duration / 60))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open slot \(Self.slotFormatter.string(from: availableSlot)), \(Int(duration / 60)) minutes")
    }
}

// MARK: - CandidateRow

private struct CandidateRow: View {
    let entry: WaitlistEntry
    let onOffer: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Customer #\(entry.customerId)")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(entry.requestedServiceType)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Waiting since \(RelativeDateTimeFormatter().localizedString(for: entry.createdAt, relativeTo: Date()))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button("Offer Slot", action: onOffer)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .font(.brandLabelSmall())
                .accessibilityLabel("Offer slot to customer #\(entry.customerId)")
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ViewModel reset helper

extension WaitlistOfferFlowViewModel {
    func reset() { offeredEntry = nil }
}
