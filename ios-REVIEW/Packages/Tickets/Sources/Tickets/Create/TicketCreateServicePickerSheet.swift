#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.3 — Services/parts quick-pick for the ticket create Devices step.
//
// Loads GET /api/v1/repair-pricing/services; shows searchable list.
// Selecting a service pre-fills device.serviceName + device.price.
// Matches the RepairServicePickerSheet used in Estimates (agent-3-b4).

// MARK: - Service option (matches server shape)

struct RepairServiceOption: Decodable, Sendable, Identifiable {
    let id: Int64
    let name: String
    let price: Double?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, price, description
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class TicketCreateServicePickerViewModel {
    private(set) var services: [RepairServiceOption] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    var searchText: String = ""

    var filtered: [RepairServiceOption] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return services }
        return services.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func load() async {
        guard services.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            services = try await api.get(
                "/api/v1/repair-pricing/services",
                query: nil,
                as: [RepairServiceOption].self
            )
        } catch {
            // Non-fatal; user can enter free-form service name
            AppLog.ui.warning("Create-flow repair services load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - View

/// Half-height sheet surfaced from the Devices step.
/// On selection calls `onPick(serviceId, name, price)`.
public struct TicketCreateServicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketCreateServicePickerViewModel
    let onPick: (_ serviceId: Int64, _ name: String, _ price: Double) -> Void

    public init(api: APIClient, onPick: @escaping (_ serviceId: Int64, _ name: String, _ price: Double) -> Void) {
        _vm = State(wrappedValue: TicketCreateServicePickerViewModel(api: api))
        self.onPick = onPick
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Group {
                    if vm.isLoading {
                        ProgressView("Loading services…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Loading repair services")
                    } else {
                        serviceList
                    }
                }
            }
            .navigationTitle("Choose Service")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search services")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel service picker")
                }
            }
        }
        .task { await vm.load() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var serviceList: some View {
        List {
            if vm.filtered.isEmpty {
                Text("No services found")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .listRowBackground(Color.bizarreSurface1)
            } else {
                ForEach(vm.filtered) { service in
                    Button {
                        onPick(service.id, service.name, service.price ?? 0)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                Text(service.name)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                if let desc = service.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if let price = service.price, price > 0 {
                                Text(formatMoney(price))
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                    .monospacedDigit()
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(service.name)\(service.price != nil && service.price! > 0 ? ", \(formatMoney(service.price!))" : "")")
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

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
#endif
