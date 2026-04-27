#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - BonjourPrinterPickerView
//
// §17 — "NWBrowser for `_ipp._tcp`, `_printer._tcp`, `_bizarre._tcp`"
//        Declare `NSBonjourServices` in Info.plist (done via write-info-plist.sh).
//        `NSLocalNetworkUsageDescription` explains local-network use.
//        Picker UI grouped by service type.
//        Icon per device class.
//        Auto-refresh every 10s.
//        Manual refresh button.
//
// Presented as a sheet from `PrinterSettingsView` → "Discover on Network" button.

public struct BonjourPrinterPickerView: View {

    // MARK: - Init

    private let onSelect: (DiscoveredPrinter) -> Void

    public init(onSelect: @escaping (DiscoveredPrinter) -> Void) {
        self.onSelect = onSelect
    }

    // MARK: - State

    @State private var vm = BonjourPrinterPickerViewModel()
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                if vm.isSearching && vm.sections.isEmpty {
                    searchingState
                } else if !vm.isSearching && vm.sections.isEmpty {
                    emptyState
                } else {
                    printerList
                }
            }
            .navigationTitle("Discover Printers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .task { await vm.start() }
            .onDisappear { Task { await vm.stop() } }
        }
    }

    // MARK: - States

    private var searchingState: some View {
        VStack(spacing: BrandSpacing.lg) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Searching for printers…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Searching for printers on the local network")
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "printer.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No printers found")
                .font(.brandHeadlineMedium())
            Text("Make sure your printer is on the same Wi-Fi network and powered on.")
                .font(.brandBodySmall())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No printers found. Make sure your printer is on the same Wi-Fi network and powered on.")
    }

    private var printerList: some View {
        List {
            ForEach(vm.sections, id: \.serviceType) { section in
                Section(section.serviceLabel) {
                    ForEach(section.printers) { printer in
                        printerRow(printer)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func printerRow(_ printer: DiscoveredPrinter) -> some View {
        Button {
            onSelect(printer)
            dismiss()
        } label: {
            HStack(spacing: BrandSpacing.base) {
                Image(systemName: printer.systemImageName)
                    .font(.system(size: 24))
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(printer.name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(printer.serviceLabel)
                        .font(.brandBodySmall())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add printer \(printer.name), \(printer.serviceLabel)")
        .accessibilityIdentifier("bonjour.printer.\(printer.id)")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("bonjour.cancel")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await vm.refresh() }
            } label: {
                if vm.isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .accessibilityLabel("Refresh printer list")
            .accessibilityIdentifier("bonjour.refresh")
        }
    }
}

// MARK: - BonjourPrinterPickerViewModel

@Observable
@MainActor
final class BonjourPrinterPickerViewModel {

    // MARK: - Published state

    struct SectionData: Identifiable {
        let id: String
        let serviceType: String
        let serviceLabel: String
        let printers: [DiscoveredPrinter]
    }

    private(set) var sections: [SectionData] = []
    private(set) var isSearching: Bool = true
    private(set) var isRefreshing: Bool = false

    // MARK: - Private

    private let browser: any BonjourPrinterBrowserProtocol
    private var streamTask: Task<Void, Never>?
    private var refreshTimerTask: Task<Void, Never>?

    init(browser: any BonjourPrinterBrowserProtocol = BonjourPrinterBrowser()) {
        self.browser = browser
    }

    // MARK: - Lifecycle

    func start() async {
        isSearching = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.browser.discoveryStream()
            for await printers in stream {
                await MainActor.run {
                    self.update(printers: printers)
                    self.isSearching = false
                }
            }
        }
        // Auto-refresh every 10s per spec.
        refreshTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, !Task.isCancelled else { break }
                await self.browser.refresh()
            }
        }
    }

    func stop() async {
        streamTask?.cancel()
        streamTask = nil
        refreshTimerTask?.cancel()
        refreshTimerTask = nil
        await browser.stop()
    }

    func refresh() async {
        isRefreshing = true
        await browser.refresh()
        isRefreshing = false
    }

    // MARK: - Private

    private func update(printers: [DiscoveredPrinter]) {
        let grouped = Dictionary(grouping: printers, by: \.serviceType)
        let order = ["_ipp._tcp", "_printer._tcp", "_bizarre._tcp"]
        sections = order.compactMap { type in
            guard let group = grouped[type], !group.isEmpty else { return nil }
            let label = group.first?.serviceLabel ?? type
            return SectionData(
                id: type,
                serviceType: type,
                serviceLabel: label,
                printers: group.sorted { $0.name < $1.name }
            )
        }
    }
}

#endif
