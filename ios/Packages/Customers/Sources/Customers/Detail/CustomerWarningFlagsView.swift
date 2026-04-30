#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

// §5 — Customer-level warning flags: "cash only", "known difficult", "VIP treatment".
// Staff-visible banner shown at the top of CustomerDetailView below the header.
// Flags stored in the customer record; toggled via PATCH /customers/:id.

// MARK: - Model

/// Staff-visible flag types per §5.
public enum CustomerWarningFlag: String, CaseIterable, Codable, Sendable {
    case cashOnly          = "cash_only"
    case knownDifficult    = "known_difficult"
    case vipTreatment      = "vip_treatment"

    public var displayName: String {
        switch self {
        case .cashOnly:       return "Cash Only"
        case .knownDifficult: return "Known Difficult"
        case .vipTreatment:   return "VIP Treatment"
        }
    }

    public var systemImage: String {
        switch self {
        case .cashOnly:       return "dollarsign.circle.fill"
        case .knownDifficult: return "exclamationmark.triangle.fill"
        case .vipTreatment:   return "star.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .cashOnly:       return .bizarreWarning
        case .knownDifficult: return .bizarreError
        case .vipTreatment:   return .bizarreOrange
        }
    }
}

// MARK: - Banner view

/// Horizontal scrolling chip row shown when a customer has any active flags.
/// Always staff-only (never shown in customer-facing surfaces).
public struct CustomerWarningFlagsBanner: View {
    public let flags: [CustomerWarningFlag]
    /// Callback to open the flag editor sheet.
    public let onEdit: (() -> Void)?

    public init(flags: [CustomerWarningFlag], onEdit: (() -> Void)? = nil) {
        self.flags = flags
        self.onEdit = onEdit
    }

    public var body: some View {
        if !flags.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                HStack(spacing: BrandSpacing.xs) {
                    Text("STAFF NOTE")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .tracking(0.8)
                    Spacer(minLength: 0)
                    if let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .accessibilityLabel("Edit customer flags")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(flags, id: \.rawValue) { flag in
                            FlagChip(flag: flag)
                        }
                    }
                }
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(Color.bizarreError.opacity(0.3), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Staff notes: \(flags.map(\.displayName).joined(separator: ", "))")
        }
    }
}

private struct FlagChip: View {
    let flag: CustomerWarningFlag

    var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: flag.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(flag.tintColor)
                .accessibilityHidden(true)
            Text(flag.displayName)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(flag.tintColor.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(flag.tintColor.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Editor sheet

/// Togglable flag editor — staff can set or clear any combination of flags.
public struct CustomerWarningFlagsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CustomerWarningFlagsEditorViewModel

    public init(api: APIClient, customerId: Int64, initialFlags: [CustomerWarningFlag]) {
        _vm = State(wrappedValue: CustomerWarningFlagsEditorViewModel(
            api: api, customerId: customerId, initialFlags: initialFlags))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section(header: Text("Staff-visible only — never shown to customers")) {
                        ForEach(CustomerWarningFlag.allCases, id: \.rawValue) { flag in
                            Toggle(isOn: Binding(
                                get: { vm.activeFlags.contains(flag) },
                                set: { on in vm.toggle(flag: flag, on: on) }
                            )) {
                                Label {
                                    Text(flag.displayName)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurface)
                                } icon: {
                                    Image(systemName: flag.systemImage)
                                        .foregroundStyle(flag.tintColor)
                                }
                            }
                            .accessibilityLabel("\(flag.displayName): \(vm.activeFlags.contains(flag) ? "active" : "inactive")")
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    if let err = vm.errorMessage {
                        Section {
                            Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                        }
                        .listRowBackground(Color.bizarreError.opacity(0.08))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Customer Flags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task {
                            await vm.save()
                            if vm.savedSuccessfully { dismiss() }
                        }
                    }
                    .disabled(vm.isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class CustomerWarningFlagsEditorViewModel {
    public var activeFlags: Set<CustomerWarningFlag>
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var savedSuccessfully = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let customerId: Int64

    public init(api: APIClient, customerId: Int64, initialFlags: [CustomerWarningFlag]) {
        self.api = api
        self.customerId = customerId
        self.activeFlags = Set(initialFlags)
    }

    public func toggle(flag: CustomerWarningFlag, on: Bool) {
        if on { activeFlags.insert(flag) } else { activeFlags.remove(flag) }
    }

    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        savedSuccessfully = false
        defer { isSaving = false }
        do {
            let req = UpdateCustomerFlagsRequest(flags: Array(activeFlags).map(\.rawValue))
            try await api.updateCustomerFlags(id: customerId, req)
            savedSuccessfully = true
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}

// MARK: - APIClient extension

public struct UpdateCustomerFlagsRequest: Encodable, Sendable {
    /// Array of flag raw values, e.g. ["cash_only", "vip_treatment"].
    public let flags: [String]

    public init(flags: [String]) { self.flags = flags }
}

public extension APIClient {
    /// `PATCH /api/v1/customers/:id/flags` — set staff warning flags.
    @discardableResult
    func updateCustomerFlags(id: Int64, _ req: UpdateCustomerFlagsRequest) async throws -> CustomerDetail {
        try await patch("/api/v1/customers/\(id)/flags", body: req, as: CustomerDetail.self)
    }
}
#endif
