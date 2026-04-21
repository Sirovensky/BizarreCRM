import SwiftUI
import DesignSystem

// MARK: - TrainingModeSettingsRow

/// §51.1 Settings row for toggling Training Mode.
/// Shows a confirmation sheet before enabling.
public struct TrainingModeSettingsRow: View {
    @Bindable var manager: TrainingModeManager

    @State private var showConfirmSheet = false
    @State private var showExitConfirmAlert = false

    public init(manager: TrainingModeManager) {
        self.manager = manager
    }

    public var body: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training Mode")
                        .font(.body)
                    Text("Switches to demo tenant with seeded data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if manager.isLoading {
                    ProgressView()
                } else {
                    Toggle("", isOn: toggleBinding)
                        .labelsHidden()
                        .accessibilityLabel("Training Mode")
                }
            }

            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showConfirmSheet) {
            confirmSheet
        }
        .alert("Exit Training Mode?", isPresented: $showExitConfirmAlert) {
            Button("Exit", role: .destructive) {
                manager.exitTrainingMode()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will return to your real tenant data.")
        }
    }

    // MARK: - Toggle binding

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { manager.isActive },
            set: { newValue in
                if newValue {
                    showConfirmSheet = true
                } else {
                    showExitConfirmAlert = true
                }
            }
        )
    }

    // MARK: - Confirmation sheet

    private var confirmSheet: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xl) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("Switch to Training Mode?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    warningRow(icon: "xmark.circle.fill", color: .red,
                               text: "No real charges will be processed")
                    warningRow(icon: "xmark.circle.fill", color: .red,
                               text: "No real SMS messages will be sent")
                    warningRow(icon: "checkmark.circle.fill", color: .green,
                               text: "Demo tenant with seeded data")
                    warningRow(icon: "checkmark.circle.fill", color: .green,
                               text: "Safe to explore all features")
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: DesignTokens.Spacing.md) {
                    Button("Enter Training Mode") {
                        showConfirmSheet = false
                        Task { await manager.enterTrainingMode() }
                    }
                    .buttonStyle(.brandGlassProminent)
                    .tint(.orange)

                    Button("Cancel", role: .cancel) {
                        showConfirmSheet = false
                    }
                    .buttonStyle(.brandGlass)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top, DesignTokens.Spacing.xl)
            .navigationTitle("Training Mode")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    @ViewBuilder
    private func warningRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
        }
    }
}
