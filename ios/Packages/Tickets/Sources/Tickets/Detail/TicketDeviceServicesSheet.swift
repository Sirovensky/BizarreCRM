#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.2 — Services & parts per device on a ticket.
//
// Catalog picker pulls from:
//   GET /api/v1/repair-pricing/services   → RepairService list
//   GET /api/v1/inventory                → inventory parts (handled by PartSkuPicker in RepairPricing pkg)
//
// Each line item = description + qty + unit price.
// Save via PATCH /api/v1/tickets/devices/:deviceId (part of the existing PUT route for devices).
//
// Auto-recalc totals: server recomputes ticket subtotal on device update.
//
// Routes confirmed:
//   GET /api/v1/repair-pricing/services (repair-pricing.routes.ts)
//   PUT /api/v1/tickets/devices/:deviceId (tickets.routes.ts)

// MARK: - Models

/// A service loaded from the repair-pricing catalog.
private struct ServiceOption: Decodable, Sendable, Identifiable {
    let id: Int64
    let name: String
    let price: Double?
    let description: String?
    let partSku: String?

    enum CodingKeys: String, CodingKey {
        case id, name, price, description
        case partSku = "part_sku"
    }
}

/// A draft service/part line being added to a device.
public struct ServiceLineDraft: Identifiable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var serviceId: Int64?
    public var serviceName: String = ""
    public var qty: Int = 1
    public var unitPrice: Double = 0

    public var lineTotal: Double { Double(qty) * unitPrice }
}

// MARK: - ViewModel

@MainActor
@Observable
final class TicketDeviceServicesViewModel {

    private(set) var services: [ServiceOption] = []
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var savedSuccessfully: Bool = false
    private(set) var errorMessage: String?

    var lines: [ServiceLineDraft]
    var searchText: String = ""

    var filtered: [ServiceOption] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return services }
        return services.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var grandTotal: Double { lines.reduce(0) { $0 + $1.lineTotal } }

    @ObservationIgnored private let api: APIClient
    let deviceId: Int64

    init(api: APIClient, deviceId: Int64, existingLines: [ServiceLineDraft] = []) {
        self.api = api
        self.deviceId = deviceId
        self.lines = existingLines.isEmpty ? [ServiceLineDraft()] : existingLines
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            services = try await api.get(
                "/api/v1/repair-pricing/services",
                query: nil,
                as: [ServiceOption].self
            )
        } catch {
            // Non-fatal — user can still enter free-form service names
            AppLog.ui.warning("Failed to load repair services: \(error.localizedDescription, privacy: .public)")
        }
    }

    func addLine(from service: ServiceOption) {
        var line = ServiceLineDraft()
        line.serviceId = service.id
        line.serviceName = service.name
        line.unitPrice = service.price ?? 0
        lines.append(line)
    }

    func addBlankLine() {
        lines.append(ServiceLineDraft())
    }

    func removeLine(at index: Int) {
        guard lines.count > 1 else { return }
        lines.remove(at: index)
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        struct ServiceLineBody: Encodable, Sendable {
            let serviceId: Int64?
            let name: String
            let qty: Int
            let unitPrice: Double

            enum CodingKeys: String, CodingKey {
                case serviceId = "service_id"
                case name, qty
                case unitPrice = "unit_price"
            }
        }

        struct DeviceServicesBody: Encodable, Sendable {
            let services: [ServiceLineBody]
        }

        let body = DeviceServicesBody(services: lines.map {
            ServiceLineBody(
                serviceId: $0.serviceId,
                name: $0.serviceName,
                qty: $0.qty,
                unitPrice: $0.unitPrice
            )
        })

        do {
            _ = try await api.put(
                "/api/v1/tickets/devices/\(deviceId)",
                body: body,
                as: TicketDetail.TicketDevice.self
            )
            savedSuccessfully = true
        } catch {
            AppLog.ui.error("Save device services failed (device \(self.deviceId)): \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct TicketDeviceServicesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketDeviceServicesViewModel
    @State private var showingServicePicker = false
    let deviceName: String
    let onSaved: () -> Void

    public init(api: APIClient, deviceId: Int64, deviceName: String, onSaved: @escaping () -> Void) {
        _vm = State(wrappedValue: TicketDeviceServicesViewModel(api: api, deviceId: deviceId))
        self.deviceName = deviceName
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    lineItemsForm
                    totalFooter
                }
            }
            .navigationTitle("Services — \(deviceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel services edit")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Add from catalog") { showingServicePicker = true }
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Add service from repair pricing catalog")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task { await vm.save() }
                    }
                    .disabled(vm.isSaving)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Save services")
                }
            }
            .sheet(isPresented: $showingServicePicker) {
                serviceCatalogPicker
            }
        }
        .task { await vm.load() }
        .onChange(of: vm.savedSuccessfully) { _, success in
            if success { onSaved(); dismiss() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Line items form

    private var lineItemsForm: some View {
        List {
            Section("Line items") {
                ForEach(Array(vm.lines.enumerated()), id: \.element.id) { idx, line in
                    ServiceLineRow(
                        line: line,
                        onUpdateName: { vm.lines[idx].serviceName = $0 },
                        onUpdateQty: { vm.lines[idx].qty = $0 },
                        onUpdatePrice: { vm.lines[idx].unitPrice = $0 },
                        onRemove: vm.lines.count > 1 ? { vm.removeLine(at: idx) } : nil
                    )
                }
            }
            Section {
                Button {
                    vm.addBlankLine()
                } label: {
                    Label("Add line item", systemImage: "plus.circle")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add blank service line item")
            }
            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Total footer (glass)

    private var totalFooter: some View {
        HStack {
            Text("Total")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text(formatMoney(vm.grandTotal))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total: \(formatMoney(vm.grandTotal))")
    }

    // MARK: - Catalog picker sheet

    private var serviceCatalogPicker: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                List {
                    if vm.filtered.isEmpty {
                        Text("No services found")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else {
                        ForEach(vm.filtered) { svc in
                            Button {
                                vm.addLine(from: svc)
                                showingServicePicker = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                        Text(svc.name)
                                            .font(.brandBodyMedium())
                                            .foregroundStyle(.bizarreOnSurface)
                                        if let desc = svc.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.brandLabelSmall())
                                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                        }
                                    }
                                    Spacer()
                                    if let price = svc.price, price > 0 {
                                        Text(formatMoney(price))
                                            .font(.brandBodyMedium())
                                            .foregroundStyle(.bizarreOnSurface)
                                            .monospacedDigit()
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(svc.name)\(svc.price != nil ? ", \(formatMoney(svc.price!))" : "")")
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.bizarreSurface1)
                            .hoverEffect(.highlight)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Repair Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search services")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingServicePicker = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - Service line row

private struct ServiceLineRow: View {
    var line: ServiceLineDraft
    let onUpdateName: (String) -> Void
    let onUpdateQty: (Int) -> Void
    let onUpdatePrice: (Double) -> Void
    let onRemove: (() -> Void)?

    @State private var priceText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            TextField("Service name", text: .init(
                get: { line.serviceName },
                set: { onUpdateName($0) }
            ))
            .font(.brandBodyMedium())
            .accessibilityLabel("Service name")

            HStack(spacing: BrandSpacing.md) {
                Stepper("Qty: \(line.qty)", value: .init(
                    get: { line.qty },
                    set: { onUpdateQty(max(1, $0)) }
                ), in: 1...99)
                .font(.brandBodyMedium())
                .accessibilityLabel("Quantity: \(line.qty)")

                Spacer()

                TextField("Price", text: .init(
                    get: { line.unitPrice == 0 ? "" : String(format: "%.2f", line.unitPrice) },
                    set: { onUpdatePrice(Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0) }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .accessibilityLabel("Unit price")
            }

            HStack {
                Text("Line total: \(formatMoney(line.lineTotal))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
                    .accessibilityLabel("Line total: \(formatMoney(line.lineTotal))")
                Spacer()
                if let remove = onRemove {
                    Button(role: .destructive) {
                        remove()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.bizarreError)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this line item")
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
#endif
