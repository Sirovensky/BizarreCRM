import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.3 Lead Delete

/// Destructive delete button with confirmation dialog.
///
/// Placed in the lead detail toolbar (⋯ menu on iPad/Mac) or at the
/// bottom of `LeadDetailView`. Fires `onDeleted` on success so the
/// parent can pop navigation.
public struct LeadDeleteButton: View {
    public let api: APIClient
    public let leadId: Int64
    public let leadName: String
    public var onDeleted: () -> Void

    @State private var showingConfirm: Bool = false
    @State private var isDeleting: Bool = false
    @State private var errorMessage: String?

    public init(api: APIClient, leadId: Int64, leadName: String, onDeleted: @escaping () -> Void = {}) {
        self.api = api
        self.leadId = leadId
        self.leadName = leadName
        self.onDeleted = onDeleted
    }

    public var body: some View {
        Group {
            if isDeleting {
                ProgressView()
                    .accessibilityLabel("Deleting lead")
            } else {
                Button(role: .destructive) {
                    showingConfirm = true
                } label: {
                    Label("Delete Lead", systemImage: "trash")
                }
                .accessibilityLabel("Delete lead \(leadName)")
                .accessibilityIdentifier("leads.delete")
            }
        }
        .confirmationDialog(
            "Delete \"\(leadName)\"?",
            isPresented: $showingConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Lead", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the lead and all associated data. This cannot be undone.")
        }
        .alert("Delete failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deleteLead(id: leadId)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ui.error("Lead delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
