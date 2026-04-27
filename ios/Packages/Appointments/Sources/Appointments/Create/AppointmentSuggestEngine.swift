import Foundation
import Networking
import Core

// MARK: - §10.8 Appointment Suggest Engine
//
// Given a customer time window preference, returns 3 nearest available slots
// that satisfy staff + resource requirements.
// Wires to `POST /appointments/suggest`.

// MARK: - Request / Response

public struct AppointmentSuggestRequest: Encodable, Sendable {
    public let durationMinutes: Int
    public let preferredWindowStart: String   // ISO-8601
    public let preferredWindowEnd: String     // ISO-8601
    public let serviceType: String?
    public let locationId: Int64?
    public let staffIds: [Int64]?

    enum CodingKeys: String, CodingKey {
        case durationMinutes = "duration_minutes"
        case preferredWindowStart = "preferred_window_start"
        case preferredWindowEnd = "preferred_window_end"
        case serviceType = "service_type"
        case locationId = "location_id"
        case staffIds = "staff_ids"
    }

    public init(
        durationMinutes: Int,
        windowStart: Date,
        windowEnd: Date,
        serviceType: String? = nil,
        locationId: Int64? = nil,
        staffIds: [Int64]? = nil
    ) {
        let fmt = ISO8601DateFormatter()
        self.durationMinutes = durationMinutes
        self.preferredWindowStart = fmt.string(from: windowStart)
        self.preferredWindowEnd = fmt.string(from: windowEnd)
        self.serviceType = serviceType
        self.locationId = locationId
        self.staffIds = staffIds
    }
}

public struct SuggestedSlot: Identifiable, Sendable, Decodable {
    public let id: UUID = UUID()
    public let start: Date
    public let end: Date
    public let staffId: Int64?
    public let staffName: String?
    public let locationId: Int64?
    public let locationName: String?
    public let score: Double   // server-computed relevance (0–1)

    public var formattedTime: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        return df.string(from: start)
    }
    public var durationMinutes: Int {
        Int(end.timeIntervalSince(start) / 60)
    }

    enum CodingKeys: String, CodingKey {
        case start, end, score
        case staffId = "staff_id"
        case staffName = "staff_name"
        case locationId = "location_id"
        case locationName = "location_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fmt = ISO8601DateFormatter()
        let startStr = try c.decode(String.self, forKey: .start)
        let endStr = try c.decode(String.self, forKey: .end)
        start = fmt.date(from: startStr) ?? Date()
        end = fmt.date(from: endStr) ?? Date()
        staffId = try c.decodeIfPresent(Int64.self, forKey: .staffId)
        staffName = try c.decodeIfPresent(String.self, forKey: .staffName)
        locationId = try c.decodeIfPresent(Int64.self, forKey: .locationId)
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName)
        score = try c.decodeIfPresent(Double.self, forKey: .score) ?? 1.0
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class AppointmentSuggestViewModel {
    public private(set) var suggestedSlots: [SuggestedSlot] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var windowStart: Date = Date()
    public var windowEnd: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    public var durationMinutes: Int = 60
    public var selectedSlot: SuggestedSlot?

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func suggest(serviceType: String? = nil, locationId: Int64? = nil) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let request = AppointmentSuggestRequest(
                durationMinutes: durationMinutes,
                windowStart: windowStart,
                windowEnd: windowEnd,
                serviceType: serviceType,
                locationId: locationId
            )
            suggestedSlots = try await api.suggestAppointmentSlots(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

#if canImport(UIKit)
import SwiftUI
import DesignSystem

public struct AppointmentSuggestView: View {
    @State private var vm: AppointmentSuggestViewModel
    let onSelect: (SuggestedSlot) -> Void

    public init(api: APIClient, onSelect: @escaping (SuggestedSlot) -> Void) {
        _vm = State(wrappedValue: AppointmentSuggestViewModel(api: api))
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Preferences") {
                    DatePicker("Window start", selection: $vm.windowStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Window end", selection: $vm.windowEnd, displayedComponents: [.date, .hourAndMinute])
                    Stepper("Duration: \(vm.durationMinutes) min",
                            value: $vm.durationMinutes, in: 15...480, step: 15)
                }
                Section {
                    Button("Find available slots") {
                        Task { await vm.suggest() }
                    }
                    .disabled(vm.isLoading)
                }
                if vm.isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Finding slots…").foregroundStyle(Color.bizarreTextSecondary)
                        }
                    }
                }
                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.bizarreError)
                    }
                }
                if !vm.suggestedSlots.isEmpty {
                    Section("Suggested slots") {
                        ForEach(vm.suggestedSlots.prefix(3)) { slot in
                            slotRow(slot)
                        }
                    }
                }
            }
            .navigationTitle("Find a slot")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func slotRow(_ slot: SuggestedSlot) -> some View {
        Button {
            onSelect(slot)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.formattedTime)
                        .font(.bizarreBody)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.bizarreTextPrimary)
                    HStack {
                        if let staff = slot.staffName {
                            Label(staff, systemImage: "person")
                        }
                        if let loc = slot.locationName {
                            Label(loc, systemImage: "mappin")
                        }
                    }
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
                }
                Spacer()
                Text("\(slot.durationMinutes) min")
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Color.bizarrePrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.formattedTime), \(slot.durationMinutes) minutes, \(slot.staffName ?? "any staff")")
        .accessibilityHint("Tap to select this slot")
    }
}
#endif

// MARK: - APIClient extension (§10.8 Suggest)

extension APIClient {
    func suggestAppointmentSlots(_ request: AppointmentSuggestRequest) async throws -> [SuggestedSlot] {
        let resp: APIResponse<[SuggestedSlot]> = try await post(
            "/api/v1/appointments/suggest", body: request
        )
        return resp.data ?? []
    }
}
