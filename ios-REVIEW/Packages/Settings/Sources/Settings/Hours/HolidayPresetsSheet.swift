import SwiftUI
import Core
import DesignSystem

// MARK: - §19 HolidayPresetsSheet

/// Lets the user bulk-add standard US holidays.
public struct HolidayPresetsSheet: View {

    @State private var selected: Set<String> = []
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let repository: any HoursRepository
    private let onDone: () async -> Void
    private let presets = HolidayPresets.usHolidays

    public init(repository: any HoursRepository, onDone: @escaping () async -> Void) {
        self.repository = repository
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            List(presets, selection: $selected) { preset in
                Label(preset.name, systemImage: "calendar")
                    .tag(preset.id)
                    .accessibilityLabel(preset.name)
            }
            #if canImport(UIKit)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("US Holiday Presets")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count) holidays") {
                        Task { await bulkAdd() }
                    }
                    .disabled(selected.isEmpty || isSaving)
                }
                #if canImport(UIKit)
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Select All") {
                            selected = Set(presets.map(\.id))
                        }
                        Spacer()
                        Button("Deselect All") {
                            selected = []
                        }
                    }
                }
                #endif
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Bulk add

    private func bulkAdd() async {
        isSaving = true
        defer { isSaving = false }

        let exceptions = presets
            .filter { selected.contains($0.id) }
            .compactMap { HolidayPresets.makeException(from: $0, isOpen: false) }

        do {
            for exception in exceptions {
                _ = try await repository.createHoliday(exception)
            }
            await onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
