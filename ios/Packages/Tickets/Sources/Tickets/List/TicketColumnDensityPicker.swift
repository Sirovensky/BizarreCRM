#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - §4.1 Column / density picker (iPad/Mac)
//
// Controls which optional columns are visible in the ticket list and the row
// density. Presented as a popover from the toolbar "Columns" button.
//
// Columns: assignee, internal note, diagnostic note, device, urgency dot.
// Stored in UserDefaults under "tickets.columnPrefs" as JSON so the setting
// survives app restarts.

/// The set of optional columns a user can show/hide in the ticket list.
public struct TicketColumnPrefs: Codable, Sendable, Equatable {
    public var showAssignee: Bool = true
    public var showInternalNote: Bool = false
    public var showDiagnosticNote: Bool = false
    public var showDevice: Bool = true
    public var showUrgencyDot: Bool = true

    public static let defaultPrefs = TicketColumnPrefs()

    // MARK: - Persistence

    private static let userDefaultsKey = "tickets.columnPrefs"

    public static func load() -> TicketColumnPrefs {
        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            let prefs = try? JSONDecoder().decode(TicketColumnPrefs.self, from: data)
        else { return .defaultPrefs }
        return prefs
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }
}

// MARK: - TicketColumnDensityPicker view

public struct TicketColumnDensityPicker: View {
    @Binding var prefs: TicketColumnPrefs
    @Environment(\.dismiss) private var dismiss

    public init(prefs: Binding<TicketColumnPrefs>) {
        _prefs = prefs
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Visible columns") {
                    Toggle("Assignee", isOn: $prefs.showAssignee)
                        .accessibilityLabel("Show assignee column")
                    Toggle("Urgency dot", isOn: $prefs.showUrgencyDot)
                        .accessibilityLabel("Show urgency dot")
                    Toggle("Device", isOn: $prefs.showDevice)
                        .accessibilityLabel("Show device column")
                    Toggle("Internal note", isOn: $prefs.showInternalNote)
                        .accessibilityLabel("Show internal note preview")
                    Toggle("Diagnostic note", isOn: $prefs.showDiagnosticNote)
                        .accessibilityLabel("Show diagnostic note preview")
                }

                Section {
                    Button("Reset to defaults") {
                        prefs = .defaultPrefs
                        prefs.save()
                    }
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Reset all column preferences to defaults")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
            .navigationTitle("Column Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        prefs.save()
                        dismiss()
                    }
                    .accessibilityLabel("Save column settings and close")
                }
            }
            .onChange(of: prefs) { _, newPrefs in
                newPrefs.save()
            }
        }
        .presentationDetents([.medium])
    }
}
#endif
