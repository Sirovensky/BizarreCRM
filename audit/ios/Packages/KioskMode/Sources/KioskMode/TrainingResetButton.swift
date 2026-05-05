import SwiftUI

// MARK: - TrainingResetButton

/// §51.2 Settings → Training → "Reset demo data" button.
/// Triggers `POST /training/reset-demo` with confirmation alert.
public struct TrainingResetButton: View {
    @Bindable var manager: TrainingModeManager

    @State private var showConfirm = false
    @State private var showSuccess = false

    public init(manager: TrainingModeManager) {
        self.manager = manager
    }

    public var body: some View {
        Group {
            Button {
                showConfirm = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle")
                    Text("Reset demo data")
                }
            }
            .disabled(!manager.isActive || manager.isLoading)
            .alert("Reset Demo Data?", isPresented: $showConfirm) {
                Button("Reset", role: .destructive) {
                    Task {
                        await manager.resetDemoData()
                        if manager.errorMessage == nil {
                            showSuccess = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reseed all demo data. Your practice records will be cleared.")
            }
            .alert("Demo data reset", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All demo data has been reseeded.")
            }

            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
