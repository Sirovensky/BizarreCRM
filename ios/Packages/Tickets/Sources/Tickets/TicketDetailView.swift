#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

public struct TicketDetailView: View {
    @State private var vm: TicketDetailViewModel
    @State private var showingEdit: Bool = false
    private let api: APIClient?

    /// Basic init — read-only detail.
    public init(repo: TicketRepository, ticketId: Int64) {
        _vm = State(wrappedValue: TicketDetailViewModel(repo: repo, ticketId: ticketId))
        self.api = nil
    }

    /// Edit-capable init — enables the "Edit" toolbar button that presents
    /// `TicketEditView`. Pass the real `APIClient` when you want writes.
    public init(repo: TicketRepository, ticketId: Int64, api: APIClient) {
        _vm = State(wrappedValue: TicketDetailViewModel(repo: repo, ticketId: ticketId))
        self.api = api
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar {
            if api != nil, case .loaded = vm.state {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingEdit = true } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let api, case let .loaded(detail) = vm.state {
                TicketEditView(api: api, ticket: detail) {
                    Task { await vm.load() }
                }
            }
        }
    }

    private var navTitle: String {
        if case let .loaded(detail) = vm.state { return detail.orderId }
        return "Ticket"
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                Text("Couldn't load ticket")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let detail):
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    CustomerCard(detail: detail)
                    InfoRow(detail: detail)
                    if !detail.devices.isEmpty {
                        DevicesSection(devices: detail.devices)
                    }
                    if !detail.notes.isEmpty {
                        NotesSection(notes: detail.notes)
                    }
                    if !detail.history.isEmpty {
                        HistorySection(history: detail.history)
                    }
                    TotalsCard(detail: detail)
                }
                .padding(BrandSpacing.base)
            }
        }
    }
}

// MARK: - Customer card

private struct CustomerCard: View {
    let detail: TicketDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Customer")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(detail.customer?.displayName ?? "Unknown")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
            if let phone = detail.customer?.phone, !phone.isEmpty,
               let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                Link(destination: url) {
                    Label(PhoneFormatter.format(phone), systemImage: "phone.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreTeal)
                }
            }
            if let email = detail.customer?.email, !email.isEmpty,
               let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "mailto:\(encoded)") {
                Link(destination: url) {
                    Label(email, systemImage: "envelope.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreTeal)
                        .textSelection(.enabled)
                }
            }
            if let org = detail.customer?.organization, !org.isEmpty {
                Label(org, systemImage: "building.2")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .cardBackground()
    }
}

// MARK: - Info row (created + assigned)

private struct InfoRow: View {
    let detail: TicketDetail

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            InfoTile(label: "Created", value: shortDate(detail.createdAt))
            if let user = detail.assignedUser {
                InfoTile(label: "Assigned", value: user.fullName.isEmpty ? "—" : user.fullName)
            }
            if let status = detail.status {
                InfoTile(label: "Status", value: status.name)
            }
        }
    }

    private func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        return String(iso.prefix(10))
    }
}

private struct InfoTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

// MARK: - Devices

private struct DevicesSection: View {
    let devices: [TicketDetail.TicketDevice]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Devices").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            ForEach(devices) { device in
                DeviceCard(device: device)
            }
        }
    }
}

private struct DeviceCard: View {
    let device: TicketDetail.TicketDevice

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(device.displayName)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)

            if let notes = device.additionalNotes, !notes.isEmpty {
                Text(notes)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if let imei = device.imei, !imei.isEmpty {
                KeyValueLine(key: "IMEI", value: imei, mono: true)
            }
            if let serial = device.serial, !serial.isEmpty {
                KeyValueLine(key: "Serial", value: serial, mono: true)
            }
            if let code = device.securityCode, !code.isEmpty {
                KeyValueLine(key: "Passcode", value: code, mono: true)
            }
            if let price = device.total, price > 0 {
                KeyValueLine(key: "Price", value: formatMoney(price))
            }

            if let parts = device.parts, !parts.isEmpty {
                Divider().overlay(Color.bizarreOutline.opacity(0.4))
                ForEach(parts) { part in
                    HStack {
                        Text("\(part.name ?? "Part")  ×\(part.quantity ?? 1)")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        if let total = part.total {
                            Text(formatMoney(total))
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .cardBackground()
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

private struct KeyValueLine: View {
    let key: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack {
            Text(key)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(mono ? .brandMono(size: 13) : .brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Notes

private struct NotesSection: View {
    let notes: [TicketDetail.TicketNote]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Notes").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    HStack {
                        Text(note.userName)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        if note.isFlagged == true {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(.bizarreError)
                        }
                        Spacer()
                        if let ts = note.createdAt {
                            Text(String(ts.prefix(16)))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    Text(note.stripped)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .cardBackground()
            }
        }
    }
}

// MARK: - History

private struct HistorySection: View {
    let history: [TicketDetail.TicketHistory]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Activity").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                ForEach(history) { entry in
                    HStack(alignment: .top, spacing: BrandSpacing.sm) {
                        Circle()
                            .fill(Color.bizarreOrange)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.stripped)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            if let ts = entry.createdAt {
                                Text(String(ts.prefix(16)))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                    }
                }
            }
            .cardBackground()
        }
    }
}

// MARK: - Totals

private struct TotalsCard: View {
    let detail: TicketDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Totals").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)

            if let subtotal = detail.subtotal, subtotal != (detail.total ?? 0) {
                row("Subtotal", value: subtotal)
            }
            if let discount = detail.discount, discount > 0 {
                row("Discount", value: -discount, tint: .bizarreSuccess)
            }
            if let tax = detail.totalTax, tax > 0 {
                row("Tax", value: tax)
            }
            Divider().overlay(Color.bizarreOutline.opacity(0.4))
            HStack {
                Text("Total").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatMoney(detail.total ?? 0))
                    .font(.brandTitleLarge()).bold()
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .cardBackground()
    }

    private func row(_ label: String, value: Double, tint: Color = .bizarreOnSurface) -> some View {
        HStack {
            Text(label).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(formatMoney(value))
                .font(.brandBodyMedium())
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Card background helper

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}
#endif
