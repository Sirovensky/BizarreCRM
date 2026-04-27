#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.3 — Hierarchical device catalog picker.
//
// Two-level picker: manufacturer → device model.
//   Level 1: list of manufacturers from GET /catalog/manufacturers.
//   Level 2: device models filtered by manufacturer + keyword search via
//            GET /catalog/devices?keyword=&manufacturer=.
//
// iPhone: NavigationStack push (manufacturer list → model list).
// iPad:   NavigationSplitView (sidebar = manufacturers, detail = models).
//
// On selection the callback receives the chosen CatalogDevice so the parent
// can pre-fill device name, family, IMEI pattern on the DraftDevice.

// MARK: - ViewModel

@MainActor
@Observable
final class CatalogDevicePickerViewModel {
    // Level 1 — manufacturers
    private(set) var manufacturers: [CatalogManufacturer] = []
    private(set) var isLoadingManufacturers: Bool = false
    private(set) var manufacturerError: String?

    // Level 2 — devices
    private(set) var catalogDevices: [CatalogDevice] = []
    private(set) var isLoadingDevices: Bool = false
    private(set) var devicesError: String?

    // Navigation state
    var selectedManufacturer: CatalogManufacturer?
    var deviceSearch: String = ""

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(api: APIClient) { self.api = api }

    func loadManufacturers() async {
        guard manufacturers.isEmpty else { return }
        isLoadingManufacturers = true
        manufacturerError = nil
        defer { isLoadingManufacturers = false }
        do {
            manufacturers = try await api.listCatalogManufacturers()
        } catch {
            manufacturerError = error.localizedDescription
        }
    }

    func selectManufacturer(_ mfr: CatalogManufacturer) async {
        selectedManufacturer = mfr
        catalogDevices = []
        await loadDevices(manufacturer: mfr.name, keyword: deviceSearch)
    }

    func onSearchChange(_ q: String) {
        deviceSearch = q
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.loadDevices(manufacturer: self.selectedManufacturer?.name, keyword: q)
        }
    }

    private func loadDevices(manufacturer: String?, keyword: String?) async {
        isLoadingDevices = true
        devicesError = nil
        defer { isLoadingDevices = false }
        do {
            catalogDevices = try await api.searchCatalogDevices(
                keyword: keyword,
                manufacturer: manufacturer
            )
        } catch {
            devicesError = error.localizedDescription
        }
    }
}

// MARK: - Sheet

public struct CatalogDevicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CatalogDevicePickerViewModel

    private let onPick: (CatalogDevice) -> Void

    public init(api: APIClient, onPick: @escaping (CatalogDevice) -> Void) {
        _vm = State(wrappedValue: CatalogDevicePickerViewModel(api: api))
        self.onPick = onPick
    }

    public var body: some View {
        NavigationStack {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .task { await vm.loadManufacturers() }
    }

    // MARK: - iPhone — NavigationStack push

    private var iPhoneLayout: some View {
        manufacturerList
            .navigationTitle("Select Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityLabel("Cancel device picker")
                }
            }
    }

    private var manufacturerList: some View {
        Group {
            if vm.isLoadingManufacturers {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.manufacturerError {
                ContentUnavailableView(
                    "Couldn't load manufacturers",
                    systemImage: "wifi.slash",
                    description: Text(err)
                )
            } else if vm.manufacturers.isEmpty {
                ContentUnavailableView("No manufacturers", systemImage: "list.dash")
            } else {
                List(vm.manufacturers) { mfr in
                    NavigationLink(mfr.name) {
                        deviceList(for: mfr)
                            .navigationTitle(mfr.name)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .accessibilityLabel("Manufacturer: \(mfr.name)")
                }
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private func deviceList(for mfr: CatalogManufacturer) -> some View {
        Group {
            if vm.isLoadingDevices {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.devicesError {
                ContentUnavailableView("Error", systemImage: "wifi.slash", description: Text(err))
            } else if vm.catalogDevices.isEmpty {
                ContentUnavailableView("No devices found", systemImage: "iphone.slash")
            } else {
                List(vm.catalogDevices) { device in
                    Button {
                        onPick(device)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            Text(device.model)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            if let year = device.releaseYear {
                                Text(String(year))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        .padding(.vertical, BrandSpacing.xs)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Device: \(device.displayName)")
                }
            }
        }
        .searchable(text: $vm.deviceSearch, prompt: "Search \(mfr.name) devices")
        .onChange(of: vm.deviceSearch) { _, q in vm.onSearchChange(q) }
        .task { await vm.selectManufacturer(mfr) }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - iPad — NavigationSplitView

    private var iPadLayout: some View {
        NavigationSplitView {
            manufacturerSidebar
                .navigationTitle("Manufacturers")
        } detail: {
            if let mfr = vm.selectedManufacturer {
                deviceList(for: mfr)
                    .navigationTitle(mfr.name)
            } else {
                ContentUnavailableView("Select a manufacturer", systemImage: "list.bullet")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.accessibilityLabel("Cancel device picker")
            }
        }
    }

    private var manufacturerSidebar: some View {
        Group {
            if vm.isLoadingManufacturers {
                ProgressView("Loading…")
            } else {
                List(vm.manufacturers, selection: $vm.selectedManufacturer) { mfr in
                    Text(mfr.name)
                        .accessibilityLabel("Manufacturer: \(mfr.name)")
                        .tag(mfr)
                }
                .onChange(of: vm.selectedManufacturer) { _, mfr in
                    guard let mfr else { return }
                    Task { await vm.selectManufacturer(mfr) }
                }
            }
        }
        .background(Color.bizarreSurface1.ignoresSafeArea())
    }
}
#endif
