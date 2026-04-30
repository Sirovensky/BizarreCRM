import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - PinManagementView
//
// §14.2 PIN management — view (as set?) / change / clear.
//
// Admin or self: can see whether a PIN is set, change the PIN, or clear it.
// Changing PIN: user enters new 4-digit PIN on `EmployeePinSheet` then confirms.
// Clearing PIN:  confirmation dialog → DELETE /api/v1/employees/:id/pin.
// Setting / changing PIN: POST /api/v1/employees/:id/pin { pin: "XXXX" }.
//
// The view is presented as a sheet from EmployeeDetailView.

@MainActor
@Observable
public final class PinManagementViewModel {
    public enum PinState: Equatable {
        case unknown
        case isSet
        case notSet
    }

    public private(set) var pinState: PinState = .unknown
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var successMessage: String?

    public var showChangePin: Bool = false
    public var showClearConfirm: Bool = false

    @ObservationIgnored private let employeeId: Int64
    @ObservationIgnored private let api: APIClient

    public init(employeeId: Int64, api: APIClient) {
        self.employeeId = employeeId
        self.api = api
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let status = try await api.getPinStatus(employeeId: employeeId)
            pinState = status.isSet ? .isSet : .notSet
        } catch {
            AppLog.ui.error("PinManagement load: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            pinState = .unknown
        }
        isLoading = false
    }

    public func setPin(_ pin: String) async {
        guard pin.count == 4, pin.allSatisfy({ $0.isNumber }) else {
            errorMessage = "PIN must be exactly 4 digits."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            try await api.setEmployeePin(employeeId: employeeId, pin: pin)
            pinState = .isSet
            successMessage = "PIN updated."
        } catch {
            AppLog.ui.error("PinManagement set: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
        showChangePin = false
    }

    public func clearPin() async {
        isLoading = true
        errorMessage = nil
        do {
            try await api.clearEmployeePin(employeeId: employeeId)
            pinState = .notSet
            successMessage = "PIN removed."
        } catch {
            AppLog.ui.error("PinManagement clear: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
        showClearConfirm = false
    }
}

public struct PinManagementView: View {
    @State private var vm: PinManagementViewModel
    // PIN entry controlled by set-pin sheet
    @State private var pendingPin: String = ""
    @State private var pinEntry: [Int] = []

    public init(employeeId: Int64, api: APIClient) {
        _vm = State(wrappedValue: PinManagementViewModel(employeeId: employeeId, api: api))
    }

    init(viewModel: PinManagementViewModel) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section {
                        pinStatusRow
                        if vm.pinState == .isSet {
                            changePinButton
                            clearPinButton
                        } else {
                            setPinButton
                        }
                    } header: {
                        Text("Clock-in PIN")
                    } footer: {
                        Text("The PIN is required to clock in and out if enforced by tenant policy. Stored securely on the server; never stored in the app.")
                            .font(.brandLabelSmall())
                    }

                    if let err = vm.errorMessage {
                        Section {
                            Text(err)
                                .foregroundStyle(.bizarreError)
                                .font(.brandBodyMedium())
                        }
                    }
                    if let success = vm.successMessage {
                        Section {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text(success).foregroundStyle(.green)
                            }
                            .font(.brandBodyMedium())
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("PIN Management")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .task { await vm.load() }
            .confirmationDialog(
                "Remove PIN",
                isPresented: $vm.showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove PIN", role: .destructive) {
                    Task { await vm.clearPin() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This employee will be able to clock in without a PIN.")
            }
            .sheet(isPresented: $vm.showChangePin) {
                newPinEntrySheet
            }
        }
    }

    // MARK: - Rows

    private var pinStatusRow: some View {
        HStack {
            Label("PIN Status", systemImage: "lock.fill")
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Group {
                switch vm.pinState {
                case .unknown:
                    ProgressView().controlSize(.small)
                case .isSet:
                    Text("Set")
                        .font(.brandLabelSmall())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                case .notSet:
                    Text("Not Set")
                        .font(.brandLabelSmall())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.bizarreOrange)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PIN status: \(vm.pinState == .isSet ? "Set" : "Not set")")
    }

    private var changePinButton: some View {
        Button {
            pinEntry = []
            vm.showChangePin = true
        } label: {
            Label("Change PIN", systemImage: "lock.rotation")
        }
        .accessibilityIdentifier("pin.change")
    }

    private var clearPinButton: some View {
        Button(role: .destructive) {
            vm.showClearConfirm = true
        } label: {
            Label("Remove PIN", systemImage: "lock.open")
        }
        .accessibilityIdentifier("pin.clear")
    }

    private var setPinButton: some View {
        Button {
            pinEntry = []
            vm.showChangePin = true
        } label: {
            Label("Set PIN", systemImage: "lock.badge.plus")
        }
        .accessibilityIdentifier("pin.set")
    }

    // MARK: - New PIN entry sheet (reuses keypad layout)

    private var newPinEntrySheet: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.xl) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                        .padding(.top, BrandSpacing.lg)

                    Text("Enter new 4-digit PIN")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)

                    // Dot indicator
                    HStack(spacing: BrandSpacing.lg) {
                        ForEach(0..<4, id: \.self) { idx in
                            Circle()
                                .fill(idx < pinEntry.count ? Color.bizarreOrange : Color.bizarreOutline)
                                .frame(width: 16, height: 16)
                                .animation(BrandMotion.snappy, value: pinEntry.count)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("PIN: \(pinEntry.count) of 4 digits entered")

                    // Keypad
                    VStack(spacing: BrandSpacing.md) {
                        ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                            HStack(spacing: BrandSpacing.md) {
                                ForEach(row, id: \.self) { digit in
                                    pinKey("\(digit)") { appendPinDigit(digit) }
                                }
                            }
                        }
                        HStack(spacing: BrandSpacing.md) {
                            Color.clear.frame(width: 80, height: 80)
                            pinKey("0") { appendPinDigit(0) }
                            pinKey("⌫", destructive: true) {
                                if !pinEntry.isEmpty { pinEntry.removeLast() }
                            }
                        }
                    }
                }
                .padding(BrandSpacing.lg)
            }
            .navigationTitle(vm.pinState == .isSet ? "Change PIN" : "Set PIN")
#if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showChangePin = false }
                }
            }
        }
    }

    private func pinKey(_ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.brandTitleLarge())
                .foregroundStyle(destructive ? .bizarreError : .bizarreOnSurface)
                .frame(width: 80, height: 80)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreSurface1, in: Circle())
        .overlay(Circle().strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5))
        .brandGlass(.regular, in: Circle(), interactive: true)
        .accessibilityLabel(destructive ? "Delete" : label)
    }

    private func appendPinDigit(_ digit: Int) {
        guard pinEntry.count < 4 else { return }
        BrandHaptics.tap()
        pinEntry.append(digit)
        if pinEntry.count == 4 {
            let pin = pinEntry.map(String.init).joined()
            Task { await vm.setPin(pin) }
        }
    }
}
