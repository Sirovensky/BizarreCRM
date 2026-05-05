import SwiftUI
import Core
import DesignSystem
import Networking

/// §43 — Reusable multi-select service picker sheet.
///
/// Designed for §16.2 POS cart intake flow: call `.sheet` on any view,
/// pass the `api`, and receive back the user's selection via `onConfirm`.
/// Not wired to PosView yet — standalone and ready for a later commit.
///
/// Example usage:
/// ```swift
/// .sheet(isPresented: $showingPicker) {
///     RepairPricingServicePicker(api: api) { selected in
///         cart.addServices(selected)
///     }
/// }
/// ```
@MainActor
public struct RepairPricingServicePicker: View {
    private let api: APIClient
    private let onConfirm: ([RepairService]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var services: [RepairService] = []
    @State private var selectedIDs: Set<Int64> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText: String = ""

    public init(api: APIClient, onConfirm: @escaping ([RepairService]) -> Void) {
        self.api = api
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                pickerContent
            }
            .navigationTitle("Select Services")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .searchable(text: $searchText, prompt: "Search services")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("repairPicker.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedIDs.count))") {
                        let picked = services.filter { selectedIDs.contains($0.id) }
                        onConfirm(picked)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityIdentifier("repairPicker.confirm")
                    .accessibilityLabel("Add \(selectedIDs.count) selected services")
                }
            }
        }
        .task { await loadServices() }
    }

    // MARK: - Content

    @ViewBuilder
    private var pickerContent: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading services")
        } else if let err = errorMessage {
            errorView(message: err)
        } else if filteredServices.isEmpty {
            emptyView
        } else {
            serviceList
        }
    }

    private var serviceList: some View {
        List(filteredServices) { service in
            ServicePickerRow(
                service: service,
                isSelected: selectedIDs.contains(service.id)
            ) {
                if selectedIDs.contains(service.id) {
                    selectedIDs.remove(service.id)
                } else {
                    selectedIDs.insert(service.id)
                }
            }
            .listRowBackground(Color.bizarreSurface1)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(searchText.isEmpty ? "No services available" : "No results for \"\(searchText)\"")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load services")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await loadServices() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filtering

    private var filteredServices: [RepairService] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return services }
        return services.filter { svc in
            svc.serviceName.lowercased().contains(q) ||
            (svc.partSku?.lowercased().contains(q) == true) ||
            (svc.family?.lowercased().contains(q) == true)
        }
    }

    // MARK: - Data

    private func loadServices() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            services = try await api.listRepairServices()
        } catch {
            AppLog.ui.error("ServicePicker load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct ServicePickerRow: View {
    let service: RepairService
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(service.serviceName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let sku = service.partSku, !sku.isEmpty {
                        Text("SKU: \(sku)")
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityLabel("Part number \(sku)")
                    }
                    if let mins = service.estimatedMinutes {
                        Text("\(mins) min")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text(formatCents(service.defaultPriceCents))
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .font(.system(size: 22))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(service.serviceName), \(formatCents(service.defaultPriceCents))\(isSelected ? ", selected" : "")")
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        return fmt.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}
