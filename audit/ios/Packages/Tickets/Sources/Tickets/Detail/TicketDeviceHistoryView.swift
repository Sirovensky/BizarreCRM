#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.5 — Device history quick action.
// GET /api/v1/tickets/device-history?imei=<imei>&serial=<serial>
// Shows all past repairs for this device regardless of customer.
// Presented as a sheet from the ticket detail view.

@MainActor
@Observable
final class TicketDeviceHistoryViewModel {
    enum LoadState { case idle, loading, loaded([TicketSummary]), empty, error(String) }
    var state: LoadState = .idle

    private let api: APIClient
    let imei: String?
    let serial: String?
    let deviceName: String?

    init(api: APIClient, imei: String?, serial: String?, deviceName: String? = nil) {
        self.api = api
        self.imei = imei
        self.serial = serial
        self.deviceName = deviceName
    }

    func load() async {
        guard !(imei ?? "").isEmpty || !(serial ?? "").isEmpty else {
            state = .empty
            return
        }
        state = .loading
        do {
            let tickets = try await api.deviceHistory(imei: imei, serial: serial)
            state = tickets.isEmpty ? .empty : .loaded(tickets)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

public struct TicketDeviceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketDeviceHistoryViewModel

    public init(api: APIClient, imei: String?, serial: String?, deviceName: String? = nil) {
        _vm = State(wrappedValue: TicketDeviceHistoryViewModel(api: api, imei: imei, serial: serial, deviceName: deviceName))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle(vm.deviceName.map { "History: \($0)" } ?? "Device History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close device history")
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .loading:
            ProgressView("Loading device history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading")

        case .empty:
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No prior repairs found for this device.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, BrandSpacing.xl)

        case .loaded(let tickets):
            List(tickets) { ticket in
                DeviceHistoryRow(ticket: ticket)
                    .listRowBackground(Color.bizarreSurface1)
                    .listRowInsets(EdgeInsets(top: BrandSpacing.sm, leading: BrandSpacing.base, bottom: BrandSpacing.sm, trailing: BrandSpacing.base))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

        case .error(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, BrandSpacing.xl)
        }
    }
}

// MARK: - Row

private struct DeviceHistoryRow: View {
    let ticket: TicketSummary

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Text(ticket.orderId)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Spacer()
                if let status = ticket.status {
                    Text(status.name)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.bizarreSurface1, in: Capsule())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            if let customer = ticket.customer {
                Text(customer.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(formatMoney(ticket.total))
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ticket \(ticket.orderId), customer \(ticket.customer?.displayName ?? "unknown"), total \(formatMoney(ticket.total))")
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}
#endif
