#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.12 Serial Scan View

/// Scan IMEI/serial number — validates format and looks up the unit.
/// Used in receiving, POS sell, and admin trace flows.
public struct SerialScanView: View {
    @State private var vm: SerialScanViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onConfirm: (SerializedItem) -> Void

    public init(api: APIClient, onConfirm: @escaping (SerializedItem) -> Void) {
        _vm = State(wrappedValue: SerialScanViewModel(api: api))
        self.onConfirm = onConfirm
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            scanField
            statusIndicator
            if let item = vm.foundItem {
                foundItemCard(item)
            }
        }
        .padding(BrandSpacing.md)
    }

    // MARK: Scan field

    private var scanField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("IMEI / Serial Number")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            HStack {
                TextField("Scan or enter serial…", text: $vm.serialInput)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .font(.brandMono(size: 16))
                    .submitLabel(.search)
                    .onSubmit { Task { await vm.lookup() } }

                if vm.isLooking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button {
                        Task { await vm.lookup() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.bizarreOrange)
                    }
                    .disabled(vm.serialInput.isEmpty)
                    .accessibilityLabel("Look up serial number")
                }
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))

            if let err = vm.validationError {
                Text(err)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreError)
                    .transition(reduceMotion ? .identity : .opacity)
                    .accessibilityLabel("Error: \(err)")
            }
        }
    }

    // MARK: Status indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if let errorMsg = vm.lookupError {
            HStack {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.bizarreError)
                Text(errorMsg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Lookup error: \(errorMsg)")
        }
    }

    // MARK: Found item card

    private func foundItemCard(_ item: SerializedItem) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.bizarreSuccess)
                Text("Unit Found").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                StatusBadge(status: item.status)
            }
            Divider()
            LabeledContent("Serial") {
                Text(item.serialNumber)
                    .font(.brandMono(size: 13))
                    .textSelection(.enabled)
            }
            LabeledContent("SKU") {
                Text(item.parentSKU)
                    .font(.brandMono(size: 13))
                    .textSelection(.enabled)
            }
            LabeledContent("Received") {
                Text(item.receivedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.brandBodyMedium())
            }

            Button {
                onConfirm(item)
            } label: {
                Label("Confirm This Unit", systemImage: "checkmark")
                    .font(.brandTitleMedium())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(!item.status.isAvailableForSale)
            .accessibilityLabel("Confirm unit \(item.serialNumber)")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Found unit, serial \(item.serialNumber), status \(item.status.displayName)")
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: SerialStatus
    var body: some View {
        Text(status.displayName)
            .font(.brandLabelLarge())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, 2)
            .background(statusColor, in: Capsule())
    }
    private var statusColor: Color {
        switch status {
        case .available: return .bizarreSuccess
        case .reserved:  return .orange
        case .sold:      return .bizarreOnSurfaceMuted
        case .returned:  return .blue
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class SerialScanViewModel {
    var serialInput: String = ""
    var isLooking: Bool = false
    var foundItem: SerializedItem?
    var validationError: String?
    var lookupError: String?

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func lookup() async {
        let sn = serialInput.trimmingCharacters(in: .whitespaces)
        guard !sn.isEmpty else { return }

        // IMEI validation (15 digits) or generic serial (≥5 chars)
        validationError = IMEIValidator.validate(sn)
        if validationError != nil && sn.count < 5 {
            return
        }
        validationError = nil
        lookupError = nil
        foundItem = nil
        isLooking = true
        defer { isLooking = false }

        do {
            foundItem = try await api.getSerial(serialNumber: sn)
        } catch {
            lookupError = "Serial not found: \(error.localizedDescription)"
        }
    }
}

// MARK: - IMEI Validator

/// Luhn-based IMEI validation. Returns error string if invalid, nil if valid or not IMEI length.
public enum IMEIValidator {
    /// Returns a validation error string if the input is a 15-digit IMEI and fails Luhn check.
    /// Returns nil if the string is valid or is not IMEI-length (non-IMEI serials are allowed).
    public static func validate(_ input: String) -> String? {
        let digits = input.filter(\.isNumber)
        guard digits.count == 15 else { return nil } // Not IMEI length — allow through
        return luhn(digits) ? nil : "IMEI checksum invalid — please re-scan."
    }

    private static func luhn(_ s: String) -> Bool {
        var sum = 0
        let reversed = s.reversed()
        for (idx, ch) in reversed.enumerated() {
            guard let d = ch.wholeNumberValue else { return false }
            if idx % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }
}
#endif
