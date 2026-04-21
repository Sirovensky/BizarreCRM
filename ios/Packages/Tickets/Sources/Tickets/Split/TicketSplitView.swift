#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §4 — Ticket split view.
/// Shows all device lines with a checkbox per line. Staff selects devices to
/// "move to new ticket" and taps "Create N new tickets".
@MainActor
public struct TicketSplitView: View {
    @Environment(\.dismiss) private var dismiss
    @State var vm: TicketSplitViewModel

    public init(vm: TicketSplitViewModel) {
        self._vm = State(wrappedValue: vm)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Split Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await vm.load() }
        .onChange(of: vm.state) { _, new in
            if case .success = new { dismiss() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading ticket devices")

        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Text(msg).foregroundStyle(.bizarreError).multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(BrandSpacing.base)

        case .idle, .loaded, .splitting, .success:
            VStack(spacing: 0) {
                instruction
                deviceList
                splitButton
            }
        }
    }

    // MARK: - Instruction

    private var instruction: some View {
        Text("Select devices to move to a NEW ticket. At least one must remain in the original.")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .multilineTextAlignment(.center)
            .padding(BrandSpacing.base)
    }

    // MARK: - Device list

    private var deviceList: some View {
        ScrollView {
            LazyVStack(spacing: BrandSpacing.sm) {
                ForEach(vm.ticket?.devices ?? []) { device in
                    DeviceSelectionRow(
                        device: device,
                        isSelected: vm.isSelected(device.id)
                    ) {
                        vm.toggleDevice(device.id)
                    }
                }
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Split button

    private var splitButton: some View {
        VStack(spacing: BrandSpacing.sm) {
            if case .failed(let msg) = vm.state {
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error: \(msg)")
            }
            Button {
                Task { await vm.split() }
            } label: {
                Group {
                    if case .splitting = vm.state {
                        ProgressView()
                    } else {
                        let count = vm.selectedCount
                        Text(count == 0
                             ? "Select devices above"
                             : "Create \(count) new ticket\(count == 1 ? "" : "s")")
                            .font(.brandBodyLarge())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(!vm.canSplit || { if case .splitting = vm.state { return true }; return false }())
            .padding(BrandSpacing.base)
            .accessibilityLabel("Create new tickets from selected devices")
        }
        .brandGlass(.clear, in: Rectangle())
    }
}

// MARK: - Device selection row

private struct DeviceSelectionRow: View {
    let device: TicketDetail.TicketDevice
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(device.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let imei = device.imei, !imei.isEmpty {
                        Text("IMEI: \(imei)")
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let notes = device.additionalNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(BrandSpacing.md)
            .background(
                isSelected
                    ? Color.bizarreOrange.opacity(0.08)
                    : Color.bizarreSurface1,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.bizarreOrange.opacity(0.6) : Color.bizarreOutline.opacity(0.4),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(device.displayName + (isSelected ? ", selected" : ", not selected"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this device")
    }
}
#endif
