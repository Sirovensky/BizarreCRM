import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - LocationFetcher

/// One-shot CLLocationManager wrapper using async/await.
#if canImport(CoreLocation)
// @unchecked Sendable: manager and continuation are accessed only on the main
// run loop via CLLocationManagerDelegate callbacks — internal synchronization is safe.
private final class LocationFetcher: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetchOnce() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        continuation?.resume(returning: loc.coordinate)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif

// MARK: - MileageEntryViewModel

@MainActor
@Observable
public final class MileageEntryViewModel {
    public var fromLocation: String = ""
    public var toLocation: String = ""
    public var fromLat: Double?
    public var fromLon: Double?
    public var toLat: Double?
    public var toLon: Double?
    public var purpose: String = ""
    public var date: Date = Date()
    public var rateCentsPerMile: Int = 67   // IRS 2024 standard rate

    public private(set) var computedMiles: Double = 0
    public private(set) var computedTotalCents: Int = 0
    public private(set) var isFetchingFromLocation: Bool = false
    public private(set) var isFetchingToLocation: Bool = false
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var savedEntryId: Int64?

    private let employeeId: Int64
    private let repository: any MileageRepository

    public init(employeeId: Int64, repository: any MileageRepository) {
        self.employeeId = employeeId
        self.repository = repository
    }

    /// Convenience init for callers that hold an `APIClient` directly.
    public init(employeeId: Int64, api: APIClient) {
        self.employeeId = employeeId
        self.repository = LiveMileageRepository(api: api)
    }

    // MARK: - Computed

    public var isValid: Bool {
        !fromLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !toLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && computedMiles > 0
    }

    public var formattedTotal: String {
        let value = Double(computedTotalCents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    // MARK: - Location auto-fill

    #if canImport(CoreLocation)
    public func fillFromCurrentLocation(endpoint: Endpoint) async {
        switch endpoint {
        case .from: isFetchingFromLocation = true
        case .to:   isFetchingToLocation = true
        }
        defer {
            isFetchingFromLocation = false
            isFetchingToLocation = false
        }
        do {
            let fetcher = LocationFetcher()
            let coord = try await fetcher.fetchOnce()
            switch endpoint {
            case .from:
                fromLat = coord.latitude
                fromLon = coord.longitude
                fromLocation = "\(String(format: "%.4f", coord.latitude)), \(String(format: "%.4f", coord.longitude))"
            case .to:
                toLat = coord.latitude
                toLon = coord.longitude
                toLocation = "\(String(format: "%.4f", coord.latitude)), \(String(format: "%.4f", coord.longitude))"
            }
            recompute()
        } catch {
            errorMessage = "Location unavailable: \(error.localizedDescription)"
        }
    }

    public enum Endpoint: Sendable { case from, to }
    #endif

    // MARK: - Recompute

    public func recompute() {
        guard let fLat = fromLat, let fLon = fromLon, let tLat = toLat, let tLon = toLon else {
            computedMiles = 0
            computedTotalCents = 0
            return
        }
        let result = MileageCalculator.reimbursementCents(
            fromLat: fLat, fromLon: fLon,
            toLat: tLat, toLon: tLon,
            rateCentsPerMile: rateCentsPerMile
        )
        computedMiles = result.miles
        computedTotalCents = result.totalCents
    }

    // MARK: - Save

    public func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        let body = CreateMileageBody(
            employeeId: employeeId,
            fromLocation: fromLocation.trimmingCharacters(in: .whitespacesAndNewlines),
            toLocation: toLocation.trimmingCharacters(in: .whitespacesAndNewlines),
            fromLat: fromLat,
            fromLon: fromLon,
            toLat: toLat,
            toLon: toLon,
            miles: computedMiles,
            rateCentsPerMile: rateCentsPerMile,
            totalCents: computedTotalCents,
            date: df.string(from: date),
            purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : purpose
        )
        do {
            let entry = try await repository.create(body)
            savedEntryId = entry.id
        } catch {
            AppLog.ui.error("Mileage save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - MileageEntrySheet

public struct MileageEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: MileageEntryViewModel

    public init(employeeId: Int64, api: APIClient) {
        _vm = State(wrappedValue: MileageEntryViewModel(employeeId: employeeId, api: api))
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: Locations
                Section("Locations") {
                    locationField(
                        label: "From",
                        text: $vm.fromLocation,
                        isFetching: vm.isFetchingFromLocation,
                        accessibilityId: "mileage.from"
                    ) {
                        #if canImport(CoreLocation)
                        Task { await vm.fillFromCurrentLocation(endpoint: .from) }
                        #endif
                    }
                    locationField(
                        label: "To",
                        text: $vm.toLocation,
                        isFetching: vm.isFetchingToLocation,
                        accessibilityId: "mileage.to"
                    ) {
                        #if canImport(CoreLocation)
                        Task { await vm.fillFromCurrentLocation(endpoint: .to) }
                        #endif
                    }
                }

                // MARK: Trip details
                Section("Trip Details") {
                    DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                        .accessibilityLabel("Trip date")
                        .accessibilityIdentifier("mileage.date")
                    TextField("Purpose", text: $vm.purpose)
                        .accessibilityLabel("Trip purpose")
                        .accessibilityIdentifier("mileage.purpose")
                }

                // MARK: Rate
                Section("Rate") {
                    HStack {
                        Text("Cents per mile")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        TextField("67", value: $vm.rateCentsPerMile, format: .number)
                            #if canImport(UIKit)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: vm.rateCentsPerMile) { _, _ in vm.recompute() }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Reimbursement rate: \(vm.rateCentsPerMile) cents per mile")
                }

                // MARK: Summary
                if vm.computedMiles > 0 {
                    Section("Summary") {
                        HStack {
                            Text("Distance")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text(String(format: "%.1f mi", vm.computedMiles))
                                .monospacedDigit()
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Distance: \(String(format: "%.1f", vm.computedMiles)) miles")

                        HStack {
                            Text("Reimbursement")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text(vm.formattedTotal)
                                .monospacedDigit()
                                .foregroundStyle(.bizarreOrange)
                                .font(.brandBodyLarge())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Reimbursement: \(vm.formattedTotal)")
                    }
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Log Mileage")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarItems }
            .onChange(of: vm.savedEntryId) { _, id in
                if id != nil { dismiss() }
            }
        }
    }

    // MARK: - Location field helper

    private func locationField(
        label: String,
        text: Binding<String>,
        isFetching: Bool,
        accessibilityId: String,
        onGPS: @escaping () -> Void
    ) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            TextField(label, text: text)
                .accessibilityLabel("\(label) location")
                .accessibilityIdentifier(accessibilityId)
                .onChange(of: text.wrappedValue) { _, _ in vm.recompute() }
            if isFetching {
                ProgressView()
                    .accessibilityLabel("Fetching \(label.lowercased()) location")
            } else {
                Button {
                    onGPS()
                } label: {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.bizarreOrange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use current location for \(label.lowercased())")
                .accessibilityIdentifier("\(accessibilityId).gps")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if vm.isSaving {
                ProgressView().accessibilityLabel("Saving mileage entry")
            } else {
                Button("Save") { Task { await vm.save() } }
                    .disabled(!vm.isValid || vm.isSaving)
                    .brandGlass()
            }
        }
    }
}
