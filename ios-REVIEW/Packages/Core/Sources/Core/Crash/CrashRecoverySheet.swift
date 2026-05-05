import SwiftUI

// §32.5 Crash recovery pipeline — Boot-time recovery sheet
// Phase 11

/// Shown at app launch when `CrashRecovery.shared.willRestartAfterCrash` is true.
///
/// Offers to restore the most recent draft from `DraftStore`.
/// After display, calls `CrashRecovery.shared.clearCrashFlag()`.
public struct CrashRecoverySheet: View {

    @Environment(\.dismiss) private var dismiss

    private let draftStore: DraftStore
    private let onRestoreDraft: () -> Void
    private let onDismiss: () -> Void

    @State private var hasDrafts = false

    public init(
        draftStore: DraftStore = DraftStore(),
        onRestoreDraft: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.draftStore = draftStore
        self.onRestoreDraft = onRestoreDraft
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Looks like we crashed last time.")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    if hasDrafts {
                        Text("We found an unsaved draft. Would you like to restore it?")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("We didn't find any unsaved drafts.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                VStack(spacing: 12) {
                    if hasDrafts {
                        Button {
                            CrashRecovery.shared.clearCrashFlag()
                            onRestoreDraft()
                            dismiss()
                        } label: {
                            Text("Restore Draft")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Restore draft")
                        .accessibilityHint("Restores your most recently unsaved draft.")
                    }

                    Button(role: .cancel) {
                        CrashRecovery.shared.clearCrashFlag()
                        onDismiss()
                        dismiss()
                    } label: {
                        Text(hasDrafts ? "Discard and Continue" : "Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(hasDrafts ? "Discard draft and continue" : "Continue")
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("App Recovery")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        CrashRecovery.shared.clearCrashFlag()
                        onDismiss()
                        dismiss()
                    }
                    .accessibilityLabel("Close recovery sheet")
                }
            }
        }
        .task {
            let drafts = await draftStore.allDrafts()
            hasDrafts = !drafts.isEmpty
        }
    }
}
