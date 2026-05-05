import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class TimezoneLocaleViewModel {

    // MARK: Supported options

    static let topCurrencies: [String] = ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "INR", "PKR", "BRL", "MXN"]
    static let topLocales: [String]    = ["en_US", "en_GB", "es_US", "es_MX", "fr_CA", "fr_FR", "de_DE", "pt_BR", "ja_JP", "zh_CN"]

    // MARK: Device defaults (captured once)

    static let deviceTimezone: String = TimeZone.current.identifier
    static let deviceCurrency: String = Locale.current.currency?.identifier ?? "USD"
    static let deviceLocale:   String = Locale.current.identifier

    // MARK: State

    var selectedTimezone: String = deviceTimezone
    var selectedCurrency: String = topCurrencies.contains(deviceCurrency) ? deviceCurrency : "USD"
    var selectedLocale:   String = topLocales.contains(deviceLocale) ? deviceLocale : "en_US"

    // MARK: Sorted timezones — current region floated to top

    var sortedTimezones: [String] {
        let all    = TimeZone.knownTimeZoneIdentifiers.sorted()
        let region = Self.deviceTimezone.components(separatedBy: "/").first ?? ""
        let top    = all.filter { $0.hasPrefix(region + "/") }
        let rest   = all.filter { !$0.hasPrefix(region + "/") }
        return top + rest
    }

    // MARK: Validation

    var isNextEnabled: Bool {
        Step4Validator.isNextEnabled(
            timezone: selectedTimezone,
            currency: selectedCurrency,
            locale: selectedLocale
        )
    }

    // MARK: Resets

    func resetTimezone() { selectedTimezone = Self.deviceTimezone }
    func resetCurrency()  { selectedCurrency = Self.topCurrencies.contains(Self.deviceCurrency) ? Self.deviceCurrency : "USD" }
    func resetLocale()    { selectedLocale   = Self.topLocales.contains(Self.deviceLocale) ? Self.deviceLocale : "en_US" }

    // MARK: Payload

    var asPayload: (timezone: String, currency: String, locale: String) {
        (selectedTimezone, selectedCurrency, selectedLocale)
    }
}

// MARK: - View  (§36.2 Step 4 — Timezone + Currency + Locale)

@MainActor
public struct TimezoneLocaleStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: (String, String, String) -> Void

    @State private var vm = TimezoneLocaleViewModel()

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (String, String, String) -> Void
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                Text("Timezone & Locale")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.top, BrandSpacing.lg)
                    .accessibilityAddTraits(.isHeader)

                Text("These settings let the app show the right times, prices, and date formats for your shop.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)

                // MARK: Timezone picker

                pickerSection(
                    label: "Timezone",
                    hint: "Sets how repair times and business hours appear",
                    resetLabel: "Use device timezone",
                    onReset: vm.resetTimezone
                ) {
                    Picker("Timezone", selection: $vm.selectedTimezone) {
                        ForEach(vm.sortedTimezones, id: \.self) { tz in
                            Text(tz.replacingOccurrences(of: "_", with: " "))
                                .tag(tz)
                        }
                    }
                    #if canImport(UIKit)
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .clipped()
                    #else
                    .pickerStyle(.menu)
                    #endif
                    .accessibilityLabel("Timezone picker")
                    .accessibilityValue(vm.selectedTimezone)
                }

                // MARK: Currency picker

                pickerSection(
                    label: "Currency",
                    hint: "Used for all prices, estimates, and invoices",
                    resetLabel: "Use device currency",
                    onReset: vm.resetCurrency
                ) {
                    Picker("Currency", selection: $vm.selectedCurrency) {
                        ForEach(TimezoneLocaleViewModel.topCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Currency picker")
                }

                // MARK: Locale picker

                pickerSection(
                    label: "Language & Region",
                    hint: "Controls number formats, date styles, and language",
                    resetLabel: "Use device locale",
                    onReset: vm.resetLocale
                ) {
                    Picker("Locale", selection: $vm.selectedLocale) {
                        ForEach(TimezoneLocaleViewModel.topLocales, id: \.self) { loc in
                            Text(localeName(loc)).tag(loc)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Language and region picker")
                    .accessibilityValue(localeName(vm.selectedLocale))
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: vm.isNextEnabled) { _, valid in
            onValidityChanged(valid)
        }
        .onAppear {
            onValidityChanged(vm.isNextEnabled)
        }
    }

    // MARK: Section builder

    @ViewBuilder
    private func pickerSection<Content: View>(
        label: String,
        hint: String,
        resetLabel: String,
        onReset: @escaping () -> Void,
        @ViewBuilder picker: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(label)
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                Spacer()
                Button(resetLabel, action: onReset)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOrange)
                    .buttonStyle(.plain)
                    .accessibilityLabel(resetLabel)
            }

            picker()
                .padding(BrandSpacing.sm)
                .background(
                    Color.bizarreSurface1.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 1)
                )

            Text(hint)
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    // MARK: Helpers

    private func localeName(_ identifier: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: identifier) ?? identifier
    }
}
