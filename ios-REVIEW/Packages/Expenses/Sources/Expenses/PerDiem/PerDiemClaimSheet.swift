import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - PerDiemClaimViewModel

@MainActor
@Observable
public final class PerDiemClaimViewModel {
    public var startDate: Date = Date()
    public var endDate: Date = Date()
    public var ratePerDayCents: Int = 5000    // $50.00 default
    public var notes: String = ""

    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var savedClaimId: Int64?

    private let employeeId: Int64
    private let api: APIClient

    public init(employeeId: Int64, api: APIClient) {
        self.employeeId = employeeId
        self.api = api
    }

    // MARK: - Computed

    public var days: Int { PerDiemCalculator.days(from: startDate, to: endDate) }

    public var totalCents: Int { PerDiemCalculator.totalCents(days: days, ratePerDayCents: ratePerDayCents) }

    public var isValid: Bool {
        endDate >= startDate && days > 0 && ratePerDayCents > 0
    }

    public var formattedTotal: String {
        let value = Double(totalCents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    public var formattedRate: String {
        let value = Double(ratePerDayCents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
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

        let body = CreatePerDiemClaimBody(
            employeeId: employeeId,
            startDate: df.string(from: startDate),
            endDate: df.string(from: endDate),
            ratePerDayCents: ratePerDayCents,
            totalCents: totalCents,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        )
        do {
            let claim: PerDiemClaim = try await api.post(
                "/api/v1/expenses/perdiem", body: body, as: PerDiemClaim.self
            )
            savedClaimId = claim.id
        } catch {
            AppLog.ui.error("Per-diem save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - PerDiemClaimSheet

public struct PerDiemClaimSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PerDiemClaimViewModel

    public init(employeeId: Int64, api: APIClient) {
        _vm = State(wrappedValue: PerDiemClaimViewModel(employeeId: employeeId, api: api))
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: Date range
                Section("Date Range") {
                    DatePicker("Start Date",
                               selection: $vm.startDate,
                               in: ...Date.distantFuture,
                               displayedComponents: .date)
                        .accessibilityLabel("Per-diem start date")
                        .accessibilityIdentifier("perdiem.startDate")
                    DatePicker("End Date",
                               selection: $vm.endDate,
                               in: vm.startDate...,
                               displayedComponents: .date)
                        .accessibilityLabel("Per-diem end date")
                        .accessibilityIdentifier("perdiem.endDate")
                }

                // MARK: Rate
                Section("Rate Per Day") {
                    HStack {
                        Text("Rate (cents)")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        TextField("5000", value: $vm.ratePerDayCents, format: .number)
                            #if canImport(UIKit)
                            .keyboardType(.numberPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .accessibilityLabel("Rate per day in cents")
                            .accessibilityIdentifier("perdiem.rate")
                    }
                    Text("\(vm.formattedRate) per day")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("\(vm.formattedRate) per day")
                }

                // MARK: Notes
                Section("Notes") {
                    TextField("Optional notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityLabel("Per-diem notes")
                        .accessibilityIdentifier("perdiem.notes")
                }

                // MARK: Summary
                Section("Summary") {
                    HStack {
                        Text("Days")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text("\(vm.days) day\(vm.days == 1 ? "" : "s")")
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(vm.days) days")

                    HStack {
                        Text("Total Reimbursement")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text(vm.formattedTotal)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOrange)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Total reimbursement: \(vm.formattedTotal)")
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Per-Diem Claim")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarItems }
            .onChange(of: vm.savedClaimId) { _, id in
                if id != nil { dismiss() }
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
                ProgressView().accessibilityLabel("Submitting per-diem claim")
            } else {
                Button("Submit") { Task { await vm.save() } }
                    .disabled(!vm.isValid)
                    .brandGlass()
                    .accessibilityLabel("Submit per-diem claim for \(vm.formattedTotal)")
            }
        }
    }
}
