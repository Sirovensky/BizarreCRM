import SwiftUI
import Observation
import Networking
import DesignSystem

// MARK: - §3 Weather-Aware Service Banner
//
// Displays a contextual service suggestion banner when the weather crosses
// certain thresholds: extreme heat (≥95 °F / 35 °C) → battery-health tip;
// extreme cold (≤32 °F / 0 °C) → screen-crack warning; rain → water-damage
// advisory.
//
// Data source: GET /api/v1/store/weather (tenant-configured city). The server
// calls a weather provider and returns a minimal payload. The banner hides
// itself on 404 / any error so shops without the feature configured are unaffected.
//
// Dismissible per weather condition per day via UserDefaults.

// MARK: - Model

public struct StoreWeatherPayload: Decodable, Sendable {
    public let tempF: Double
    public let condition: String   // "clear", "rain", "snow", "storm", …
    public let city: String

    public init(tempF: Double = 70, condition: String = "clear", city: String = "") {
        self.tempF = tempF
        self.condition = condition
        self.city = city
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tempF     = (try? c.decode(Double.self, forKey: .tempF))     ?? 70
        self.condition = (try? c.decode(String.self, forKey: .condition)) ?? "clear"
        self.city      = (try? c.decode(String.self, forKey: .city))      ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case tempF = "temp_f"
        case condition, city
    }
}

// MARK: - Service suggestion derived from weather

public struct WeatherServiceSuggestion: Sendable, Equatable {
    public let icon: String
    public let title: String
    public let body: String
    public let dismissKey: String   // unique per condition-bucket per calendar day

    public static func from(_ w: StoreWeatherPayload) -> WeatherServiceSuggestion? {
        let dayTag = Self.dayTag()
        if w.tempF >= 95 {
            return .init(icon: "thermometer.sun.fill",
                         title: "Hot weather — battery tip",
                         body: "Offer proactive battery health checks. Heat degrades lithium cells faster; upsell now before summer repairs spike.",
                         dismissKey: "weather.heat.\(dayTag)")
        }
        if w.tempF <= 32 {
            return .init(icon: "thermometer.snowflake",
                         title: "Freezing temps — screen advisory",
                         body: "Cold makes screens brittle. Remind walk-ins to warm devices before dropping them — reduces screen-crack liability.",
                         dismissKey: "weather.cold.\(dayTag)")
        }
        let lower = w.condition.lowercased()
        if lower.contains("rain") || lower.contains("storm") || lower.contains("drizzle") {
            return .init(icon: "cloud.rain.fill",
                         title: "Rain — water-damage upsell",
                         body: "Rain days drive water-damage repairs. Pin a \"Water-damaged? We fix it\" social post and prep desiccant kits.",
                         dismissKey: "weather.rain.\(dayTag)")
        }
        return nil
    }

    private static func dayTag() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class WeatherServiceBannerViewModel {
    public enum State: Sendable {
        case loading
        case visible(StoreWeatherPayload, WeatherServiceSuggestion)
        case hidden
    }

    public private(set) var state: State = .loading
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        guard case .loading = state else { return }
        do {
            let weather = try await api.get(
                "/api/v1/store/weather",
                as: StoreWeatherPayload.self
            )
            guard let suggestion = WeatherServiceSuggestion.from(weather) else {
                state = .hidden
                return
            }
            // Check if already dismissed today for this condition bucket.
            if UserDefaults.standard.bool(forKey: suggestion.dismissKey) {
                state = .hidden
                return
            }
            state = .visible(weather, suggestion)
        } catch {
            state = .hidden
        }
    }

    public func dismiss(key: String) {
        UserDefaults.standard.set(true, forKey: key)
        state = .hidden
    }
}

// MARK: - View

public struct WeatherServiceBanner: View {
    @State private var vm: WeatherServiceBannerViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: WeatherServiceBannerViewModel(api: api))
    }

    public var body: some View {
        switch vm.state {
        case .loading, .hidden:
            EmptyView()
        case .visible(let weather, let suggestion):
            BannerCard(weather: weather, suggestion: suggestion) {
                vm.dismiss(key: suggestion.dismissKey)
            }
            .task { /* already loaded */ }
        }
    }
}

// MARK: - Card

private struct BannerCard: View {
    let weather: StoreWeatherPayload
    let suggestion: WeatherServiceSuggestion
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(suggestion.title)
                    .font(.brandLabelMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // Temperature pill
                Text("\(Int(weather.tempF))°F · \(weather.city)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                // Dismiss
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss weather banner")
            }

            Text(suggestion.body)
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOrange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.title). \(suggestion.body). Dismiss button available.")
    }
}
