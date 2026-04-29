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
// iPhone: full-screen NavigationStack step. No progress bar at step 1 (bar
//   appears from step 2 onwards per mockup).
// iPad:   rendered as inspector-pane content (compact rows, no List grouping).

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
                ipadContent
            } else {
                iPhoneContent
            }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneContent: some View {
        VStack(spacing: 0) {
            // No progress bar on step 1 per mockup (bar only appears from 1c onward)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if coordinator.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .accessibilityLabel("Loading devices…")
                    } else if let error = devicePickerVM.errorMessage {
                        errorRow(message: error)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    } else {
                        // "On file" section
                        let savedOptions = devicePickerVM.options.filter {
                            if case .addNew = $0 { return false }
                            return true
                        }
                        if !savedOptions.isEmpty {
                            sectionLabel("On file · \(savedOptions.count)")
                                .padding(.horizontal, 16)

                            VStack(spacing: 8) {
                                ForEach(savedOptions) { option in
                                    deviceCard(option: option)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // "Add new" section
                        sectionLabel("Add new")
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        addNewDeviceCard
                            .padding(.horizontal, 16)
                    }
                    Spacer().frame(height: 20)
                }
                .padding(.top, 8)
                .padding(.bottom, 80) // room for CTA
            }

            confirmCTA
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .navigationTitle("Pick device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Customer name chip — matches mockup 1b "Sarah M." pill in nav bar.
                if let name = coordinator.customerDisplayName {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.bizarreOnSurface)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.bizarreSurface1, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 1))
                        .accessibilityLabel("Customer: \(name)")
                }
            }
        }
        .task { await devicePickerVM.load(customerId: coordinator.draft.customerId) }
    }

    // MARK: - iPad layout (inspector-pane friendly — no List container)

    private var ipadContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if coordinator.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .accessibilityLabel("Loading devices…")
                    } else if let error = devicePickerVM.errorMessage {
                        errorRow(message: error)
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                    } else {
                        let savedOptions = devicePickerVM.options.filter {
                            if case .addNew = $0 { return false }
                            return true
                        }

                        // On file section
                        inspectorSectionLabel("On file · \(savedOptions.count)")
                            .padding(.horizontal, 18)

                        VStack(spacing: 0) {
                            ForEach(savedOptions) { option in
                                inspectorDeviceRow(option: option)
                                Divider()
                                    .overlay(Color.bizarreOutline.opacity(0.4))
                                    .padding(.leading, 18)
                            }
                        }

                        // Add new section
                        inspectorSectionLabel("Add new")
                            .padding(.horizontal, 18)

                        inspectorAddNewRow
                    }
                }
                .padding(.bottom, 16)
            }

            // Cancel/Continue buttons live in the parent
            // `iPadRepairInspectorPane` footer — embedding another set here
            // gave the user two pairs of buttons (one mid-screen, one at the
            // bottom). Removed.
        }
        .task { await devicePickerVM.load(customerId: coordinator.draft.customerId) }
    }

    // MARK: - Shared card-style device rows (iPhone)

    /// Full card-style row matching mockup 1b: emoji icon in 40×40 tile,
    /// primary/subtitle text, selected checkmark circle.
    private func deviceCard(option: PosDeviceOption) -> some View {
        let isSelected = coordinator.draft.selectedDeviceOption == option
        return Button {
            devicePickerVM.select(option)
            coordinator.setDevice(option)
            BrandHaptics.tap()
        } label: {
            HStack(spacing: 12) {
                // Device icon tile 40×40
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.bizarreOnSurface.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.bizarreOnSurface.opacity(0.08), lineWidth: 1)
                        )
                    Text(option.emojiIcon)
                        .font(.system(size: 20))
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.bizarreOnSurface)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    if let subtitle = option.displaySubtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                    if let warranty = option.warrantyLine {
                        Text(warranty)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.bizarreSuccess)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Selection indicator
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.bizarreOrange)
                            .frame(width: 20, height: 20)
                        Text("✓")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.7))
                    }
                } else {
                    Circle()
                        .stroke(Color.bizarreOnSurface.opacity(0.2), lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.bizarreSurface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected
                                    ? Color.bizarreOrange.opacity(0.38)
                                    : Color.bizarreOnSurface.opacity(0.07),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.displayLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("repairFlow.device.\(option.id)")
    }

    /// "Add new device" dashed card with gradient + icon, subtitle, scan camera button, ›.
    private var addNewDeviceCard: some View {
        let isSelected = coordinator.draft.selectedDeviceOption == .addNew
        return Button {
            devicePickerVM.select(.addNew)
            coordinator.setDevice(.addNew)
            BrandHaptics.tap()
        } label: {
            HStack(spacing: 12) {
                // Gradient "+" tile 40×40 — top: primary-bright, bottom: primary (mockup 1b)
                ZStack {
                    LinearGradient(
                        colors: [Color.bizarreOrangeBright, Color.bizarreOrange],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("+")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Color.bizarreOnPrimary)
                }
                .frame(width: 40, height: 40)
                .shadow(color: Color.bizarreOrange.opacity(0.22), radius: 12, y: 4)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add new device")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.bizarreOrange)
                    Text("Scan IMEI or pick make / model / condition")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Inline scan button
                Button {
                    AppLog.pos.info("RepairFlow: scan button tapped — awaiting camera integration")
                } label: {
                    Text("📷")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .background(Color.bizarreOnSurface.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bizarreOnSurface.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan device IMEI")

                Text("›")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.bizarreOrange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                            .foregroundStyle(Color.bizarreOrange.opacity(0.4))
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add new device")
        .accessibilityHint("Tap to add a new device manually, or use the camera button to scan IMEI")
        .accessibilityIdentifier("repairFlow.device.add-new")
    }

    // MARK: - iPad inspector rows (compact, no card backgrounds — inline list style)

    private func inspectorDeviceRow(option: PosDeviceOption) -> some View {
        let isSelected = coordinator.draft.selectedDeviceOption == option
        return Button {
            devicePickerVM.select(option)
            coordinator.setDevice(option)
            BrandHaptics.tap()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.bizarreOnSurface.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bizarreOnSurface.opacity(0.08), lineWidth: 1))
                    Text(option.emojiIcon)
                        .font(.system(size: 18))
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayLabel)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.bizarreOnSurface)
                    if let subtitle = option.displaySubtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                    if let warranty = option.warrantyLine {
                        Text(warranty)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.bizarreSuccess)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    ZStack {
                        Circle().fill(Color.bizarreOrange).frame(width: 20, height: 20)
                        Text("✓").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                    }
                } else {
                    Circle().stroke(Color.bizarreOnSurface.opacity(0.2), lineWidth: 1.5).frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.bizarreOrange.opacity(0.06) : Color.clear
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.displayLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var inspectorAddNewRow: some View {
        HStack(spacing: 12) {
            Button {
                devicePickerVM.select(.addNew)
                coordinator.setDevice(.addNew)
                BrandHaptics.tap()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        LinearGradient(
                            colors: [Color.bizarreOrangeBright, Color.bizarreOrange],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("+")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(Color.bizarreOnPrimary)
                    }
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add new device")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(Color.bizarreOrange)
                        Text("Scan IMEI or pick make / model")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("›").font(.system(size: 16)).foregroundStyle(Color.bizarreOrange)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add new device")

            Button {
                AppLog.pos.info("RepairFlow: scan button tapped — awaiting camera integration")
            } label: {
                Text("📷")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(Color.bizarreOnSurface.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bizarreOnSurface.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan device IMEI")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.bizarreOrange.opacity(0.3), Color.bizarreOrange.opacity(0.3)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.4)
            .foregroundStyle(Color.bizarreOnSurfaceMuted)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    private func inspectorSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Color.bizarreOnSurfaceMuted)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func errorRow(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
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
            HStack(spacing: 6) {
                Text("Continue → describe issue")
                    .font(.subheadline.weight(.bold))
                Text("›")
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                coordinator.draft.selectedDeviceOption == nil
                    ? Color.bizarreOrange.opacity(0.4)
                    : Color.bizarreOrange,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(Color.bizarreOnPrimary)
        }
        .buttonStyle(.plain)
        .disabled(coordinator.draft.selectedDeviceOption == nil || coordinator.isLoading)
        .accessibilityLabel("Continue to describe issue")
        .accessibilityHint("Advances to step 2 of 4")
        .accessibilityIdentifier("repairFlow.devicePicker.continue")
    }
}
#endif
