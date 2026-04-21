import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - Models

struct LanguageRegionResponse: Codable, Sendable {
    var locale: String?
    var timezone: String?
    var currency: String?
    var dateFormat: String?
    var numberFormat: String?
}

// MARK: - ViewModel

@MainActor
@Observable
public final class LanguageRegionViewModel: Sendable {

    var locale: String = Locale.current.identifier
    var timezone: String = TimeZone.current.identifier
    var currency: String = "USD"
    var dateFormat: String = "MM/dd/yyyy"
    var numberFormat: String = "1,234.56"

    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?

    var availableLocales: [String] {
        Locale.availableIdentifiers.sorted()
    }

    var availableTimezones: [String] {
        TimeZone.knownTimeZoneIdentifiers.sorted()
    }

    var availableCurrencies: [String] {
        Locale.commonISOCurrencyCodes.sorted()
    }

    var dateFormatOptions: [String] {
        ["MM/dd/yyyy", "dd/MM/yyyy", "yyyy-MM-dd", "dd.MM.yyyy", "MMM d, yyyy"]
    }

    var numberFormatOptions: [String] {
        ["1,234.56", "1.234,56", "1 234.56", "1234.56"]
    }

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let api else { return }
        do {
            let resp: LanguageRegionResponse = try await api.get(
                "/settings/organization", as: LanguageRegionResponse.self
            )
            locale = resp.locale ?? Locale.current.identifier
            timezone = resp.timezone ?? TimeZone.current.identifier
            currency = resp.currency ?? "USD"
            dateFormat = resp.dateFormat ?? "MM/dd/yyyy"
            numberFormat = resp.numberFormat ?? "1,234.56"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let api else { return }
        do {
            let body = LanguageRegionResponse(
                locale: locale, timezone: timezone,
                currency: currency, dateFormat: dateFormat, numberFormat: numberFormat
            )
            _ = try await api.put("/settings/organization", body: body, as: LanguageRegionResponse.self)
            successMessage = "Language & Region saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct LanguageRegionPage: View {
    @State private var vm: LanguageRegionViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: LanguageRegionViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("Language & locale") {
                Picker("Locale", selection: $vm.locale) {
                    ForEach(vm.availableLocales, id: \.self) { id in
                        Text(Locale(identifier: id).localizedString(forIdentifier: id) ?? id)
                            .tag(id)
                    }
                }
                .accessibilityLabel("Locale")
                .accessibilityIdentifier("langRegion.locale")
            }

            Section("Time zone") {
                Picker("Timezone", selection: $vm.timezone) {
                    ForEach(vm.availableTimezones, id: \.self) { tz in
                        Text(tz.replacingOccurrences(of: "_", with: " ")).tag(tz)
                    }
                }
                .accessibilityLabel("Timezone")
                .accessibilityIdentifier("langRegion.timezone")
            }

            Section("Currency") {
                Picker("Currency", selection: $vm.currency) {
                    ForEach(vm.availableCurrencies, id: \.self) { code in
                        Text("\(code) — \(Locale.current.localizedString(forCurrencyCode: code) ?? code)")
                            .tag(code)
                    }
                }
                .accessibilityLabel("Currency")
                .accessibilityIdentifier("langRegion.currency")
            }

            Section("Formats") {
                Picker("Date format", selection: $vm.dateFormat) {
                    ForEach(vm.dateFormatOptions, id: \.self) { fmt in
                        Text(fmt).tag(fmt)
                    }
                }
                .accessibilityLabel("Date format")
                .accessibilityIdentifier("langRegion.dateFormat")

                Picker("Number format", selection: $vm.numberFormat) {
                    ForEach(vm.numberFormatOptions, id: \.self) { fmt in
                        Text(fmt).tag(fmt)
                    }
                }
                .accessibilityLabel("Number format")
                .accessibilityIdentifier("langRegion.numberFormat")
            }

            if let msg = vm.errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(msg)")
                }
            }

            if let msg = vm.successMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle")
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityLabel(msg)
                }
            }
        }
        .navigationTitle("Language & Region")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving)
                    .accessibilityIdentifier("langRegion.save")
            }
        }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading {
                ProgressView().accessibilityLabel("Loading language settings")
            }
        }
    }
}
