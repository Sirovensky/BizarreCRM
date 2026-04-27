import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - §19.6 Ticket # format — {prefix}-{year}-{seq} tenant-configurable.

// MARK: - Models

public struct TicketNumberFormatConfig: Equatable, Sendable {
    /// Raw format string, e.g. "T-{YYYY}{MM}-{SEQ:5}"
    public var format: String
    /// How often the SEQ counter resets.
    public var seqReset: SeqReset
    /// Current preview derived from the format string.
    public var preview: String {
        TicketNumberFormatter.preview(format: format)
    }

    public enum SeqReset: String, CaseIterable, Identifiable, Sendable {
        case never   = "never"
        case yearly  = "yearly"
        case monthly = "monthly"
        case daily   = "daily"

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .never:   return "Never"
            case .yearly:  return "Yearly"
            case .monthly: return "Monthly"
            case .daily:   return "Daily"
            }
        }
    }

    public static let defaults = TicketNumberFormatConfig(
        format: "T-{YYYY}{MM}-{SEQ:5}",
        seqReset: .never
    )
}

// MARK: - Formatter helper

public enum TicketNumberFormatter {
    /// Returns a sample rendered number using today's date and sequence 1.
    public static func preview(format: String) -> String {
        let now = Date()
        let cal = Calendar.current
        let year4  = String(format: "%04d", cal.component(.year,  from: now))
        let year2  = String(year4.suffix(2))
        let month  = String(format: "%02d", cal.component(.month, from: now))
        let day    = String(format: "%02d", cal.component(.day,   from: now))

        var result = format
        result = result.replacingOccurrences(of: "{YYYY}", with: year4)
        result = result.replacingOccurrences(of: "{YY}",   with: year2)
        result = result.replacingOccurrences(of: "{MM}",   with: month)
        result = result.replacingOccurrences(of: "{DD}",   with: day)
        result = result.replacingOccurrences(of: "{LOC}",  with: "MAIN")
        result = result.replacingOccurrences(of: "{INIT}", with: "JD")

        // Replace {SEQ:N} with zero-padded sequence 1
        let seqPattern = #"\{SEQ:(\d+)\}"#
        if let regex = try? NSRegularExpression(pattern: seqPattern),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let widthRange = Range(match.range(at: 1), in: result),
           let width = Int(result[widthRange]) {
            let padded = String(format: "%0\(width)d", 1)
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: padded
            )
        }

        return result
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class TicketNumberFormatViewModel {

    public var config: TicketNumberFormatConfig = .defaults
    public var savedConfig: TicketNumberFormatConfig = .defaults
    public var isLoading: Bool = false
    public var isSaving: Bool = false
    public var errorMessage: String?
    public var successMessage: String?

    public var isDirty: Bool { config != savedConfig }

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let wire: TicketNumberFormatWire = try await api.get("settings/tickets/number-format")
            let loaded = TicketNumberFormatConfig(
                format: wire.format ?? TicketNumberFormatConfig.defaults.format,
                seqReset: TicketNumberFormatConfig.SeqReset(rawValue: wire.seq_reset ?? "never") ?? .never
            )
            config = loaded
            savedConfig = loaded
        } catch {
            // Use defaults if endpoint doesn't exist yet
        }
    }

    public func save() async {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }
        do {
            let body = TicketNumberFormatWire(format: config.format, seq_reset: config.seqReset.rawValue)
            try await api.put("settings/tickets/number-format", body: body)
            savedConfig = config
            successMessage = "Format saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func discard() {
        config = savedConfig
    }
}

// MARK: - Wire

private struct TicketNumberFormatWire: Codable {
    let format: String?
    let seq_reset: String?
}

// MARK: - View

public struct TicketNumberFormatPage: View {

    @State private var vm: TicketNumberFormatViewModel

    private let tokenHints: [(token: String, description: String)] = [
        ("{YYYY}", "4-digit year, e.g. 2026"),
        ("{YY}",   "2-digit year, e.g. 26"),
        ("{MM}",   "2-digit month, e.g. 04"),
        ("{DD}",   "2-digit day, e.g. 15"),
        ("{LOC}",  "Location code, e.g. MAIN"),
        ("{INIT}", "Creator initials, e.g. JD"),
        ("{SEQ:N}", "Zero-padded seq, e.g. {SEQ:5} → 00123"),
    ]

    public init(api: APIClientProtocol) {
        _vm = State(initialValue: TicketNumberFormatViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Form {
                formatSection
                previewSection
                seqResetSection
                tokenSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Ticket Number Format")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if vm.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await vm.save() }
                    }
                    .disabled(!vm.isDirty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var formatSection: some View {
        Section {
            TextField("Format string", text: $vm.config.format)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled(true)
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel("Ticket number format")
                .accessibilityIdentifier("ticketFormat.string")
                .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Format string")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("Use tokens from the reference below. Server enforces uniqueness; collisions auto-retry.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section {
            HStack {
                Text("Preview")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(vm.config.preview)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.bizarreOrange)
                    .textSelection(.enabled)
                    .accessibilityLabel("Preview: \(vm.config.preview)")
            }
            .listRowBackground(Color.bizarreSurface1)

            if let err = vm.errorMessage {
                Text(err).foregroundStyle(.bizarreError).font(.brandLabelSmall())
                    .listRowBackground(Color.bizarreSurface1)
            }
            if let ok = vm.successMessage {
                Text(ok).foregroundStyle(.bizarreSuccess).font(.brandLabelSmall())
                    .listRowBackground(Color.bizarreSurface1)
            }
        }
    }

    @ViewBuilder
    private var seqResetSection: some View {
        Section {
            Picker("SEQ reset cadence", selection: $vm.config.seqReset) {
                ForEach(TicketNumberFormatConfig.SeqReset.allCases) { opt in
                    Text(opt.displayName).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityIdentifier("ticketFormat.seqReset")
        } header: {
            Text("Sequence reset")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("Controls when the SEQ counter resets to 1. Existing IDs are unaffected when you change the format.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    @ViewBuilder
    private var tokenSection: some View {
        Section {
            ForEach(tokenHints, id: \.token) { hint in
                HStack {
                    Text(hint.token)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.bizarreOrange)
                        .textSelection(.enabled)
                        .accessibilityLabel("Token: \(hint.token)")
                    Spacer()
                    Text(hint.description)
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .listRowBackground(Color.bizarreSurface1)
            }
        } header: {
            Text("Available tokens")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TicketNumberFormatPage(api: MockAPIClient())
    }
}
#endif
