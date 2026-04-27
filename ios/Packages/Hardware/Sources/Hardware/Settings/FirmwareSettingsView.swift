#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - FirmwareSettingsView
//
// §17 Firmware management — Settings → Hardware → Firmware
//
// Shows firmware version for each paired device (card terminal + receipt/label
// printers). Surfaces an "outdated" banner and lets a manager apply updates.
//
// Rules (from §17 ActionPlan):
//   - Never auto-apply without consent.
//   - Warn against firmware update during open hours.
//   - Show expected downtime duration before confirming.
//   - Keep previous firmware available for rollback where supported.
//   - Log every firmware attempt + result.
//
// iPhone: scrollable Form.
// iPad: same Form in the detail pane of HardwareSettingsView's NavigationSplitView.

public struct FirmwareSettingsView: View {

    // MARK: - Dependencies

    @State private var manager: FirmwareManager
    @State private var showUpdateConfirm: FirmwareInfo? = nil
    @State private var showRollbackConfirm: FirmwareInfo? = nil
    @State private var isOpenHours: Bool = false   // Injected or toggled for demo
    @State private var updateResult: FirmwareUpdateResultBanner? = nil

    public init(manager: FirmwareManager) {
        _manager = State(initialValue: manager)
    }

    // MARK: - Body

    public var body: some View {
        List {
            // Open-hours toggle (mirrors real tenant config; defaulting off here)
            openHoursSection

            if manager.firmwareInfos.isEmpty && !manager.isLoading {
                emptySection
            } else {
                ForEach(manager.firmwareInfos, id: \.deviceName) { info in
                    Section(info.kind.rawValue) {
                        firmwareRow(info)
                    }
                }
            }

            // Update policy picker
            policySection
        }
        .navigationTitle("Firmware")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if manager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking firmware versions…")
                } else {
                    Button {
                        Task { await manager.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh firmware versions")
                }
            }
        }
        // Update confirmation sheet
        .confirmationDialog(
            updateConfirmTitle,
            isPresented: Binding(
                get: { showUpdateConfirm != nil },
                set: { if !$0 { showUpdateConfirm = nil } }
            ),
            titleVisibility: .visible,
            presenting: showUpdateConfirm
        ) { info in
            Button("Update Firmware", role: .destructive) {
                Task {
                    let result = await manager.applyUpdate(for: info, isOpenHours: isOpenHours)
                    updateResult = FirmwareUpdateResultBanner(info: info, result: result)
                    showUpdateConfirm = nil
                }
            }
            Button("Cancel", role: .cancel) { showUpdateConfirm = nil }
        } message: { info in
            Text("This will take approximately \(info.estimatedDowntimeMinutes) minute(s) and the device will be temporarily offline during the update.")
        }
        // Rollback confirmation sheet
        .confirmationDialog(
            "Roll Back Firmware?",
            isPresented: Binding(
                get: { showRollbackConfirm != nil },
                set: { if !$0 { showRollbackConfirm = nil } }
            ),
            titleVisibility: .visible,
            presenting: showRollbackConfirm
        ) { info in
            Button("Roll Back", role: .destructive) {
                Task {
                    let result = await manager.rollback(for: info)
                    updateResult = FirmwareUpdateResultBanner(info: info, result: result)
                    showRollbackConfirm = nil
                }
            }
            Button("Cancel", role: .cancel) { showRollbackConfirm = nil }
        } message: { _ in
            Text("Rolling back will restore the previous firmware version. Only use this if the current version is causing issues.")
        }
        // Result banner
        .alert(
            updateResult?.title ?? "",
            isPresented: Binding(
                get: { updateResult != nil },
                set: { if !$0 { updateResult = nil } }
            )
        ) {
            Button("OK") { updateResult = nil }
        } message: {
            Text(updateResult?.body ?? "")
        }
        .task { await manager.refresh() }
    }

    // MARK: - Open hours toggle

    private var openHoursSection: some View {
        Section {
            Toggle(isOn: $isOpenHours) {
                Label("Shop is currently open", systemImage: "storefront")
            }
            .accessibilityLabel("Shop open hours toggle")
            .accessibilityHint("When enabled, firmware updates are blocked unless you change the policy.")
        } footer: {
            Text("Firmware updates are blocked during open hours (unless policy is set to 'Immediately').")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty state

    private var emptySection: some View {
        Section {
            Label("No hardware paired", systemImage: "bolt.slash")
                .foregroundStyle(.secondary)
                .accessibilityLabel("No hardware is currently paired. Pair a card terminal or printer to manage firmware.")
        }
    }

    // MARK: - Per-device firmware row

    @ViewBuilder
    private func firmwareRow(_ info: FirmwareInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(info.deviceName)
                    .font(.headline)
                Spacer()
                versionBadge(info)
            }

            HStack(spacing: 16) {
                versionDetail(label: "Installed", version: info.currentVersion)
                versionDetail(label: "Latest", version: info.latestVersion)
            }

            if !info.isUpToDate {
                outdatedWarning(info)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(info.deviceName). Installed: \(info.currentVersion). Latest: \(info.latestVersion). " +
            (info.isUpToDate ? "Up to date." : "Update available.")
        )
    }

    private func versionBadge(_ info: FirmwareInfo) -> some View {
        Group {
            if info.isUpToDate {
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Label("Update available", systemImage: "arrow.up.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func versionDetail(label: String, version: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(version)
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func outdatedWarning(_ info: FirmwareInfo) -> some View {
        Divider()
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if isOpenHours && manager.updatePolicy == .afterHours {
                    Label("Update available — close register first", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("~\(info.estimatedDowntimeMinutes) min downtime during update", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 4) {
                Button("Update") { showUpdateConfirm = info }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isOpenHours && manager.updatePolicy == .afterHours)
                    .accessibilityLabel("Update firmware for \(info.deviceName)")

                if info.rollbackAvailable {
                    Button("Rollback") { showRollbackConfirm = info }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.secondary)
                        .accessibilityLabel("Roll back firmware for \(info.deviceName)")
                }
            }
        }
    }

    // MARK: - Policy section

    private var policySection: some View {
        Section {
            Picker("Update Policy", selection: $manager.updatePolicy) {
                ForEach(FirmwareUpdatePolicy.allCases, id: \.self) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Firmware update policy: \(manager.updatePolicy.rawValue)")
        } header: {
            Text("Update Policy")
        } footer: {
            Text("""
            "After hours" blocks updates when the shop-open toggle is on. \
            "Immediately" allows updates at any time (manager confirms). \
            "Manual" hides update prompts.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Confirmation title

    private var updateConfirmTitle: String {
        guard let info = showUpdateConfirm else { return "Update Firmware?" }
        return "Update \(info.deviceName) to \(info.latestVersion)?"
    }
}

// MARK: - FirmwareUpdateResultBanner (local result model)

private struct FirmwareUpdateResultBanner {
    let info: FirmwareInfo
    let result: FirmwareUpdateResult

    var title: String {
        switch result {
        case .success:       return "Firmware Updated"
        case .failed:        return "Update Failed"
        case .cancelled:     return "Update Cancelled"
        case .noPreviousVersion: return "Rollback Unavailable"
        }
    }

    var body: String {
        switch result {
        case .success(let v):  return "\(info.deviceName) is now on version \(v)."
        case .failed(let r):   return "Could not update \(info.deviceName): \(r)"
        case .cancelled:       return "The firmware update was cancelled."
        case .noPreviousVersion: return "\(info.deviceName) does not support rollback."
        }
    }
}

#endif
