#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

/// §6.4 — Pick scope (category / location / "all") then start a stocktake session.
public struct StocktakeStartView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: StocktakeStartViewModel

    // Navigation to the scan view once the session is created.
    @State private var launchSessionId: Int64?

    private let api: APIClient

    private let knownCategories = [
        "All", "Accessories", "Batteries", "Cables", "Chargers",
        "Cases", "Displays", "Memory", "Parts", "Tools", "Other"
    ]

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: StocktakeStartViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Scope") {
                    Picker("Category", selection: $vm.selectedCategory) {
                        ForEach(knownCategories, id: \.self) { cat in
                            Text(cat).tag(cat == "All" ? "" : cat)
                        }
                    }
                    .accessibilityLabel("Category filter")

                    TextField("Location (optional)", text: $vm.selectedLocation)
                        .accessibilityLabel("Location filter, optional")
                }

                Section("Session") {
                    TextField("Name (optional)", text: $vm.sessionName)
                        .accessibilityLabel("Session name, optional")
                    Text("Scope: \(vm.scopeDescription)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                    .accessibilityLabel("Error: \(err)")
                }

                Section {
                    Button {
                        Task { await startSession() }
                    } label: {
                        if vm.isStarting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Start stocktake")
                                .font(.brandBodyLarge())
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(vm.isStarting)
                    .tint(.bizarreOrange)
                    .accessibilityLabel(vm.isStarting ? "Starting stocktake" : "Start stocktake")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New Stocktake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel new stocktake")
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { launchSessionId != nil },
                set: { if !$0 { launchSessionId = nil } }
            )) {
                if let id = launchSessionId {
                    StocktakeScanView(api: api, sessionId: id)
                }
            }
        }
    }

    private func startSession() async {
        await vm.start()
        if let session = vm.startedSession {
            launchSessionId = session.id
        }
    }
}
#endif
