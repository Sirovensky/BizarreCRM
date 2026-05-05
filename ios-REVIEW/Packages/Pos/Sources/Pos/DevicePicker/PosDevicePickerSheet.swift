#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PosDevicePickerSheet
//
// Sheet presented when a cashier sells a repair service to a customer with
// saved assets. Shows the customer's devices plus two sentinel rows:
// "No specific device" and "Add a new device".
//
// iPad:  detents [.medium, .large], .hoverEffect(.highlight) on rows.
// iPhone: identical detents, no hover effect (no pointing device).

public struct PosDevicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var vm: PosDevicePickerViewModel

    let customerId: Int64
    let onConfirm: @MainActor (PosDeviceOption) -> Void
    let onAddNew: @MainActor () -> Void

    public init(
        customerId: Int64,
        repository: any PosDevicePickerRepository,
        onConfirm: @escaping @MainActor (PosDeviceOption) -> Void,
        onAddNew: @escaping @MainActor () -> Void
    ) {
        self.customerId = customerId
        self.onConfirm = onConfirm
        self.onAddNew = onAddNew
        _vm = State(initialValue: PosDevicePickerViewModel(repository: repository))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Which device?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { cancelButton }
            .task { await vm.load(customerId: customerId) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.options.isEmpty {
            loadingView
        } else if let err = vm.errorMessage, vm.options.isEmpty {
            errorView(err)
        } else {
            optionList
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading devices")
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load devices")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") {
                Task { await vm.load(customerId: customerId) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("devicePicker.retryButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Option list

    private var optionList: some View {
        List(vm.options) { option in
            optionRow(option)
                .listRowBackground(rowBackground(option))
                .accessibilityIdentifier(rowAccessibilityId(option))
                .accessibilityAddTraits(vm.selected == option ? .isSelected : [])
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func optionRow(_ option: PosDeviceOption) -> some View {
        if option == .addNew {
            addNewRow
        } else {
            Button {
                handleTap(option)
            } label: {
                DevicePickerRow(option: option, isSelected: vm.selected == option)
            }
            .buttonStyle(.plain)
            .modifier(HoverHighlightModifier())
        }
    }

    private var addNewRow: some View {
        Button {
            dismiss()
            onAddNew()
        } label: {
            DevicePickerRow(option: .addNew, isSelected: false)
        }
        .buttonStyle(.plain)
        .modifier(HoverHighlightModifier())
        .foregroundStyle(.bizarreOrange)
        .accessibilityLabel("Add a new device")
    }

    private func handleTap(_ option: PosDeviceOption) {
        BrandHaptics.success()
        vm.select(option)
        onConfirm(option)
        dismiss()
    }

    private func rowBackground(_ option: PosDeviceOption) -> Color {
        vm.selected == option
            ? Color.bizarreOrangeContainer.opacity(0.25)
            : Color.bizarreSurface1
    }

    private func rowAccessibilityId(_ option: PosDeviceOption) -> String {
        switch option {
        case .asset(let id, _, _):
            return "devicePicker.asset.\(id)"
        case .noSpecificDevice:
            return "devicePicker.noSpecific"
        case .addNew:
            return "devicePicker.addNew"
        }
    }

    // MARK: - Toolbar

    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                vm.clearSelection()
                dismiss()
            }
            .accessibilityIdentifier("devicePicker.cancel")
        }
    }
}

// MARK: - DevicePickerRow

private struct DevicePickerRow: View {
    let option: PosDeviceOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: option.systemImage)
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(option.displayLabel)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let sub = option.displaySubtitle {
                    Text(sub)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Selected")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - HoverHighlightModifier
//
// Applies .hoverEffect(.highlight) on iPad (where a pointing device exists)
// and is a no-op on iPhone. Gated via Platform.isCompact so the modifier
// never adds overhead on compact-width devices.

private struct HoverHighlightModifier: ViewModifier {
    func body(content: Content) -> some View {
        if Platform.isCompact {
            content
        } else {
            content.hoverEffect(.highlight)
        }
    }
}

#endif
