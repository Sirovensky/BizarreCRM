import SwiftUI
import DesignSystem

// MARK: - ElevationManagerPinSheet

/// Stub sheet that collects a manager PIN and grants a temporary elevation
/// for the specified capability scope (§47.8).
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showElevation) {
///     ElevationManagerPinSheet(scope: "invoices.refund") { granted in
///         if granted { proceedWithRefund() }
///     }
/// }
/// ```
public struct ElevationManagerPinSheet: View {

    // MARK: Properties

    public let scope: String
    public let onResult: @Sendable (Bool) -> Void

    @State private var pin: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    // Inject the session; tests can provide a custom instance via DI.
    private let elevationSession: ElevationSession

    // MARK: Init

    public init(
        scope: String,
        elevationSession: ElevationSession = ElevationSession.shared,
        onResult: @escaping @Sendable (Bool) -> Void
    ) {
        self.scope = scope
        self.elevationSession = elevationSession
        self.onResult = onResult
    }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A manager PIN is required to perform: **\(scope)**")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Manager PIN") {
                    SecureField("Enter PIN", text: $pin)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityLabel("Manager PIN field")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Approve")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(pin.count < 4 || isSubmitting)

                    Button("Cancel", role: .cancel) {
                        onResult(false)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Elevation Required")
            .inlineNavigationTitle()
        }
    }

    // MARK: Private

    @MainActor
    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Stub validation: any PIN of 4+ digits is accepted in this iteration.
        // Host app should replace this with a real manager PIN API call.
        guard pin.count >= 4, pin.allSatisfy(\.isNumber) else {
            errorMessage = "PIN must be at least 4 digits."
            return
        }

        await elevationSession.elevate(scope: scope)
        onResult(true)
        dismiss()
    }
}
