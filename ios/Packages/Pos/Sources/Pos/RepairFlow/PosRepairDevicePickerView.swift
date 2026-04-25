#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosRepairDevicePickerView (Frame 1b)
//
// Step 1 of the repair intake flow. Displays the customer's saved devices
// fetched from GET /api/v1/customers/:id/assets plus a merged "Add new device"
// row with an inline camera-scan button.
//
// iPhone: full-screen NavigationStack step.
// iPad:   rendered inside an `.inspector` pane alongside the ticket detail.

public struct PosRepairDevicePickerView: View {

    @Bindable private var coordinator: PosRepairFlowCoordinator
    private let devicePickerVM: PosDevicePickerViewModel

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        coordinator: PosRepairFlowCoordinator,
        devicePickerVM: PosDevicePickerViewModel
    ) {
        self.coordinator = coordinator
        self.devicePickerVM = devicePickerVM
    }

    public var body: some View {
        Group {
            if hSizeClass == .regular {
                // iPad: inspector-pane rendering
                ipadContent
            } else {
                // iPhone: full-screen step
                iPhoneContent
            }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneContent: some View {
        VStack(spacing: 0) {
            stepProgressBar

            ScrollView {
                VStack(spacing: BrandSpacing.sm) {
                    if coordinator.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .accessibilityLabel("Loading devices…")
                    } else if let error = devicePickerVM.errorMessage {
                        errorRow(message: error)
                    } else {
                        deviceList
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.md)
                .padding(.bottom, BrandSpacing.xxl)
            }

            confirmCTA
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.md)
        }
        .navigationTitle(RepairStep.pickDevice.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await devicePickerVM.load(customerId: coordinator.draft.customerId) }
    }

    // MARK: - iPad layout
    //
    // On iPad this view renders INSIDE the `.inspector` pane (PosRegisterLayout
    // hosts the inspector slot). It should look like a compact panel sheet —
    // NOT a full-screen NavigationStack step. No NavigationTitle here; the
    // inspector header (step X / 4 label) is owned by the parent layout.

    private var ipadContent: some View {
        VStack(spacing: 0) {
            stepProgressBar
                .padding(.top, BrandSpacing.xs)

            ScrollView {
                VStack(spacing: BrandSpacing.sm) {
                    // Section header
                    Text("SAVED DEVICES")
                        .font(.brandLabelSmall())
                        .tracking(1.4)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.md)

                    if coordinator.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .accessibilityLabel("Loading devices…")
                    } else if let error = devicePickerVM.errorMessage {
                        errorRow(message: error)
                            .padding(.horizontal, BrandSpacing.base)
                    } else {
                        deviceListIPad
                    }
                }
                .padding(.bottom, BrandSpacing.xl)
            }

            confirmCTA
                .padding(.horizontal, BrandSpacing.base)
                .padding(.bottom, BrandSpacing.md)
        }
        .task { await devicePickerVM.load(customerId: coordinator.draft.customerId) }
    }

    /// iPad-specific device list: lighter card style with hover effects.
    @ViewBuilder
    private var deviceListIPad: some View {
        VStack(spacing: BrandSpacing.xs) {
            ForEach(devicePickerVM.options) { option in
                if case .addNew = option {
                    addNewDeviceRowIPad
                } else {
                    deviceRowIPad(option: option)
                }
            }
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    private func deviceRowIPad(option: PosDeviceOption) -> some View {
        Button {
            devicePickerVM.select(option)
            coordinator.setDevice(option)
            BrandHaptics.tap()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: option.systemImage)
                    .font(.title3)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(option.displayLabel)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)

                    if let subtitle = option.displaySubtitle {
                        // IMEI/serial subtitles are text-selectable per CLAUDE.md
                        Text(subtitle)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)

                if coordinator.draft.selectedDeviceOption == option {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        coordinator.draft.selectedDeviceOption == option
                            ? Color.bizarreOrange.opacity(0.6)
                            : Color.bizarreOutline.opacity(0.35),
                        lineWidth: coordinator.draft.selectedDeviceOption == option ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.displayLabel)
        .accessibilityHint(option.displaySubtitle ?? "")
        .accessibilityAddTraits(coordinator.draft.selectedDeviceOption == option ? .isSelected : [])
        .accessibilityIdentifier("repairFlow.device.\(option.id)")
    }

    /// Merged "Add new device" row — iPad card style with hover.
    private var addNewDeviceRowIPad: some View {
        HStack(spacing: BrandSpacing.sm) {
            Button {
                devicePickerVM.select(.addNew)
                coordinator.setDevice(.addNew)
                BrandHaptics.tap()
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.bizarreOrange)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text("Add new device")
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOrange)
                        Text("Scan IMEI or pick make / model")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }

                    Spacer(minLength: 0)

                    if coordinator.draft.selectedDeviceOption == .addNew {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add new device")

            Button {
                AppLog.pos.info("RepairFlow: scan button tapped — awaiting camera integration")
            } label: {
                Label("Scan", systemImage: "camera.viewfinder")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.bizarreOrange)
                    .padding(BrandSpacing.xs)
                    .background(Color.bizarreOrange.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Scan device barcode")
            .accessibilityIdentifier("repairFlow.devicePicker.scan")
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .foregroundStyle(Color.bizarreOrange.opacity(0.35))
        )
        .hoverEffect(.highlight)
        .accessibilityIdentifier("repairFlow.device.add-new")
    }

    // MARK: - Shared sub-views

    private var stepProgressBar: some View {
        ProgressView(value: RepairStep.pickDevice.progressPercent, total: 100)
            .progressViewStyle(.linear)
            .tint(.bizarreOrange)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityLabel(RepairStep.pickDevice.accessibilityDescription)
            .accessibilityValue("\(Int(RepairStep.pickDevice.progressPercent))%")
    }

    @ViewBuilder
    private var deviceList: some View {
        ForEach(devicePickerVM.options) { option in
            if case .addNew = option {
                addNewDeviceRow
            } else {
                deviceRow(option: option)
            }
        }
    }

    private func deviceRow(option: PosDeviceOption) -> some View {
        Button {
            devicePickerVM.select(option)
            coordinator.setDevice(option)
            BrandHaptics.tap()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: option.systemImage)
                    .font(.title3)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(option.displayLabel)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    if let subtitle = option.displaySubtitle {
                        Text(subtitle)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                }

                Spacer(minLength: 0)

                if coordinator.draft.selectedDeviceOption == option {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, BrandSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.displayLabel)
        .accessibilityHint(option.displaySubtitle ?? "")
        .accessibilityAddTraits(coordinator.draft.selectedDeviceOption == option ? .isSelected : [])
        .accessibilityIdentifier("repairFlow.device.\(option.id)")
    }

    /// Merged "Add new device" row with inline camera scan button (not two rows).
    private var addNewDeviceRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            // Primary tap selects the "add new" sentinel.
            Button {
                devicePickerVM.select(.addNew)
                coordinator.setDevice(.addNew)
                BrandHaptics.tap()
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.bizarreOrange)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    Text("Add new device")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOrange)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    Spacer(minLength: 0)

                    if coordinator.draft.selectedDeviceOption == .addNew {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add new device")
            .accessibilityHint("Tap to add a new device manually")

            // Inline scan button — visually merged into the same row.
            Button {
                // TODO: launch DataScannerViewController for IMEI/serial scan
                // Requires Info.plist NSCameraUsageDescription already present.
                AppLog.pos.info("RepairFlow: scan button tapped — awaiting camera integration")
            } label: {
                Label("Scan", systemImage: "camera.viewfinder")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.bizarreOrange)
                    .padding(BrandSpacing.xs)
                    .background(Color.bizarreOrange.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Scan device barcode")
            .accessibilityHint("Opens camera to scan IMEI or serial number")
            .accessibilityIdentifier("repairFlow.devicePicker.scan")
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityIdentifier("repairFlow.device.add-new")
    }

    private func errorRow(message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.leading)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    private var confirmCTA: some View {
        Button {
            coordinator.advance()
            BrandHaptics.tapMedium()
        } label: {
            HStack {
                Text("Continue → describe issue")
                    .font(.brandTitleSmall())
                Image(systemName: "chevron.right")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(coordinator.draft.selectedDeviceOption == nil || coordinator.isLoading)
        .accessibilityLabel("Continue to describe issue")
        .accessibilityHint("Advances to step 2 of 4")
        .accessibilityIdentifier("repairFlow.devicePicker.continue")
    }
}
#endif
