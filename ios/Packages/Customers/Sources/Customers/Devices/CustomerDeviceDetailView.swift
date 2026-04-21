#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

// §5.7 — Device detail sheet with ticket history.

struct CustomerDeviceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let api: APIClient
    let customerId: Int64
    let device: CustomerDevice

    @State private var tickets: [TicketSummary] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.base) {
                        deviceHeader
                        ticketHistorySection
                    }
                    .padding(BrandSpacing.base)
                }
            }
            .navigationTitle(device.deviceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadTickets() }
        }
        .presentationDetents([.large])
    }

    private var deviceHeader: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 32))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.deviceName)
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let imei = device.imei, !imei.isEmpty {
                        Text("IMEI: \(imei)")
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                    } else if let serial = device.serial, !serial.isEmpty {
                        Text("S/N: \(serial)")
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                    }
                    if let added = device.addedAt {
                        Text("Added \(String(added.prefix(10)))")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var ticketHistorySection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Ticket history")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, BrandSpacing.md)
            } else if tickets.isEmpty {
                Text("No tickets on file for this device.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(tickets) { t in
                    ticketRow(t)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func ticketRow(_ t: TicketSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.orderId)
                    .font(.brandMono(size: 14))
                    .foregroundStyle(.bizarreOnSurface)
                if let device = t.firstDevice?.deviceName, !device.isEmpty {
                    Text(device)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let status = t.status?.name {
                Text(status)
                    .font(.brandLabelSmall())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.bizarreSurface2, in: Capsule())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ticket \(t.orderId)\(t.status?.name.map { ", \($0)" } ?? "")")
    }

    private func loadTickets() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            tickets = try await api.customerDeviceTickets(customerId: customerId, deviceId: device.id)
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}
#endif
