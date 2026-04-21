#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.12 Serial Trace Report (admin)

/// Admin view: where is a specific serial number? Shows status + history.
public struct SerialTraceReport: View {
    @State private var vm: SerialTraceViewModel
    @State private var searchInput: String = ""

    public init(api: APIClient) {
        _vm = State(wrappedValue: SerialTraceViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    content
                }
            }
            .navigationTitle("Serial Trace")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("Enter IMEI or serial number", text: $searchInput)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .font(.brandMono(size: 15))
                .submitLabel(.search)
                .onSubmit { Task { await vm.trace(serialNumber: searchInput) } }
            if vm.isLoading {
                ProgressView().scaleEffect(0.8)
            } else if !searchInput.isEmpty {
                Button {
                    searchInput = ""
                    vm.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:
            idleState
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .found(let item):
            traceDetail(item)
        case .notFound(let msg):
            notFoundState(msg)
        }
    }

    private var idleState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Enter a serial number or IMEI above to trace a unit.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Enter serial number to begin trace")
    }

    private func notFoundState(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "questionmark.diamond.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreError)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.xl)
        .accessibilityLabel("Serial not found: \(msg)")
    }

    private func traceDetail(_ item: SerializedItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                statusHeader(item)
                infoGrid(item)
                historySection(item)
            }
            .padding(BrandSpacing.md)
        }
    }

    // MARK: Status header

    private func statusHeader(_ item: SerializedItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.serialNumber)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Text(item.parentSKU)
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
            Spacer()
            statusBadge(item.status)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Serial \(item.serialNumber), SKU \(item.parentSKU), status \(item.status.displayName)")
    }

    private func statusBadge(_ status: SerialStatus) -> some View {
        Text(status.displayName)
            .font(.brandLabelLarge())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(statusColor(status), in: Capsule())
    }

    private func statusColor(_ status: SerialStatus) -> Color {
        switch status {
        case .available: return .bizarreSuccess
        case .reserved:  return .orange
        case .sold:      return .bizarreError
        case .returned:  return .blue
        }
    }

    // MARK: Info grid

    private func infoGrid(_ item: SerializedItem) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            infoRow("Received", item.receivedAt.formatted(date: .complete, time: .omitted))
            if let soldAt = item.soldAt {
                infoRow("Sold", soldAt.formatted(date: .complete, time: .omitted))
            }
            if let invoiceId = item.invoiceId {
                infoRow("Invoice #", String(invoiceId))
            }
            if let locationId = item.locationId {
                infoRow("Location ID", String(locationId))
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
    }

    // MARK: History section

    private func historySection(_ item: SerializedItem) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Status History")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                historyRow(date: item.receivedAt, event: "Received", icon: "shippingbox.fill", color: .bizarreSuccess)
                if let soldAt = item.soldAt {
                    historyRow(date: soldAt, event: "Sold", icon: "cart.fill", color: .bizarreOrange)
                }
                if item.status == .returned {
                    historyRow(date: Date(), event: "Returned", icon: "arrow.uturn.backward.circle.fill", color: .blue)
                }
            }
        }
    }

    private func historyRow(date: Date, event: String, icon: String, color: Color) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event) on \(date.formatted(date: .abbreviated, time: .shortened))")
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class SerialTraceViewModel {
    enum State: Sendable {
        case idle
        case loading
        case found(SerializedItem)
        case notFound(String)
    }

    var state: State = .idle
    var isLoading: Bool = false

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func trace(serialNumber: String) async {
        let sn = serialNumber.trimmingCharacters(in: .whitespaces)
        guard !sn.isEmpty else { return }
        state = .loading
        isLoading = true
        defer { isLoading = false }
        do {
            let item = try await api.getSerial(serialNumber: sn)
            state = .found(item)
        } catch {
            state = .notFound("No unit found for serial '\(sn)'.")
        }
    }

    func clear() {
        state = .idle
    }
}
#endif
