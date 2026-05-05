#if canImport(UIKit)
import SwiftUI
import UIKit
import DesignSystem
import Networking
import Core

// MARK: - §6.8 Asset Return Flow
//
// Inspect → mark available flow for a loaned loaner asset.
// Wired from AssetManagerView swipe action + context menu when status == .loaned.
//
// Server: POST /api/v1/loaners/:id/return  (see AssetEndpoints.returnAsset)
// Cross-domain note: any BlockChyp deposit hold release is owned by Agent 1 / POS
// (§28 / Payments) — this sheet only exposes a `releaseHold` toggle that the
// caller can wire to that subsystem; the toggle's value is forwarded as part of
// the `notes` field for audit visibility.

@MainActor
@Observable
public final class AssetReturnViewModel {

    public let asset: InventoryAsset

    /// Inspection condition (e.g. "Good", "Cracked screen"). Required.
    public var conditionIn: String

    /// Post-return status — `.available` (re-shelf) or `.retired` (write-off).
    public var newStatus: AssetStatus = .available

    /// Free-form inspection notes.
    public var notes: String = ""

    /// User-facing request to release a deposit hold (forwarded to caller; we
    /// only annotate the audit note — actual BlockChyp release lives in POS).
    public var releaseDepositHold: Bool = false

    public private(set) var isSaving = false
    public internal(set) var errorMessage: String?
    public private(set) var didSucceed = false

    @ObservationIgnored private let api: APIClient

    public init(asset: InventoryAsset, api: APIClient) {
        self.asset = asset
        self.api = api
        // Pre-fill with the condition the asset went out with so staff only edit deltas.
        self.conditionIn = asset.condition ?? ""
    }

    public var canSubmit: Bool {
        !conditionIn.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    /// Compose the audit note that's sent to the server.
    /// Visible in the loaner_history audit row so managers can reconcile holds later.
    public var composedNotes: String? {
        var lines: [String] = []
        let trimmed = notes.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { lines.append(trimmed) }
        if releaseDepositHold {
            lines.append("[Hold release requested by inspector]")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public func submit() async {
        guard canSubmit else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let request = ReturnAssetRequest(
            conditionIn: conditionIn.trimmingCharacters(in: .whitespaces),
            newStatus: newStatus,
            notes: composedNotes
        )

        do {
            _ = try await api.returnAsset(id: asset.id, request: request)
            didSucceed = true
        } catch {
            errorMessage = AppError.from(error).errorDescription ?? "Return failed."
            AppLog.ui.error("AssetReturn submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - View

public struct AssetReturnSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var vm: AssetReturnViewModel
    private let onCompleted: () -> Void

    public init(asset: InventoryAsset, api: APIClient, onCompleted: @escaping () -> Void) {
        _vm = State(wrappedValue: AssetReturnViewModel(asset: asset, api: api))
        self.onCompleted = onCompleted
    }

    public var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    compactForm
                } else {
                    regularForm
                }
            }
            .navigationTitle("Return Loaner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .disabled(vm.isSaving)
            .onChange(of: vm.didSucceed) { _, succeeded in
                if succeeded {
                    onCompleted()
                    dismiss()
                }
            }
        }
        // iPad: present as wider sheet so the inspection + status panels sit side-by-side.
        .frame(
            minWidth: horizontalSizeClass == .regular ? 560 : nil,
            minHeight: horizontalSizeClass == .regular ? 520 : nil
        )
    }

    // MARK: iPhone (single-column form)
    private var compactForm: some View {
        Form {
            assetSummarySection
            inspectionSection
            statusSection
            notesSection
            errorSection
        }
    }

    // MARK: iPad (two-column scrollable layout)
    private var regularForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                Form { assetSummarySection }
                    .frame(height: 140)
                    .scrollDisabled(true)
                HStack(alignment: .top, spacing: BrandSpacing.lg) {
                    Form {
                        inspectionSection
                        notesSection
                    }
                    Form {
                        statusSection
                        errorSection
                    }
                }
            }
            .padding(BrandSpacing.lg)
        }
    }

    // MARK: Sections

    private var assetSummarySection: some View {
        Section("Asset") {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundStyle(Color.bizarreWarning)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(vm.asset.name).font(.bizarreBody).fontWeight(.medium)
                    if let serial = vm.asset.serial {
                        Text(serial)
                            .font(.brandMono(size: 12))
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                    if let loanedTo = vm.asset.loanedTo {
                        Text("Loaned to \(loanedTo)")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                }
            }
        }
    }

    private var inspectionSection: some View {
        Section("Inspection") {
            TextField("Condition (required)", text: $vm.conditionIn)
                .textInputAutocapitalization(.sentences)
                .accessibilityLabel("Return condition")
        }
    }

    private var statusSection: some View {
        Section("After return") {
            Picker("New status", selection: $vm.newStatus) {
                Text("Available — re-shelf").tag(AssetStatus.available)
                Text("Retire — write off").tag(AssetStatus.retired)
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Toggle(isOn: $vm.releaseDepositHold) {
                Label("Request deposit hold release", systemImage: "creditcard.trianglebadge.exclamationmark")
            }
            .accessibilityHint("Flags the audit note so payments staff can release any BlockChyp hold.")
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $vm.notes)
                .frame(minHeight: 80)
                .accessibilityLabel("Inspection notes")
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let err = vm.errorMessage {
            Section {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.bizarreError)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(vm.isSaving ? "Returning…" : "Return") {
                Task { await vm.submit() }
            }
            .disabled(!vm.canSubmit)
        }
    }
}

#endif
