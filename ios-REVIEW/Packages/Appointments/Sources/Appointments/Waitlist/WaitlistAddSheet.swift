import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - WaitlistAddSheet

public struct WaitlistAddSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var customerId: String = ""
    @State private var serviceType: String = ""
    @State private var note: String = ""
    @State private var windowStart: Date = Date()
    @State private var windowEnd: Date = Date().addingTimeInterval(3600)
    @State private var preferredWindows: [PreferredWindow] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    customerSection
                    serviceSection
                    windowSection
                    windowListSection
                    noteSection
                    if let err = errorMessage {
                        Section {
                            Text(err)
                                .foregroundStyle(.bizarreError)
                                .font(.brandLabelSmall())
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add to Waitlist")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Add") { Task { await submit() } }
                            .disabled(customerId.isEmpty || serviceType.isEmpty)
                    }
                }
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Sections

    private var customerSection: some View {
        Section("Customer") {
            TextField("Customer ID", text: $customerId)
                #if !os(macOS)
                .keyboardType(.numberPad)
                #endif
                .accessibilityLabel("Customer ID")
        }
    }

    private var serviceSection: some View {
        Section("Service Type") {
            TextField("e.g. Haircut, Massage", text: $serviceType)
                .accessibilityLabel("Requested service type")
        }
    }

    private var windowSection: some View {
        Section("Add Preferred Window") {
            DatePicker("From", selection: $windowStart, displayedComponents: [.date, .hourAndMinute])
                .accessibilityLabel("Preferred window start")
            DatePicker("To", selection: $windowEnd, in: windowStart..., displayedComponents: [.date, .hourAndMinute])
                .accessibilityLabel("Preferred window end")
            Button("Add Window") {
                let w = PreferredWindow(start: windowStart, end: windowEnd)
                preferredWindows = preferredWindows + [w]
            }
            .disabled(windowEnd <= windowStart)
            .foregroundStyle(.bizarreOrange)
            .accessibilityLabel("Add preferred time window")
        }
    }

    private var windowListSection: some View {
        Group {
            if !preferredWindows.isEmpty {
                Section("Preferred Windows") {
                    ForEach(preferredWindows.indices, id: \.self) { idx in
                        let w = preferredWindows[idx]
                        HStack {
                            Text(windowLabel(w))
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                        }
                    }
                    .onDelete { indices in
                        preferredWindows = preferredWindows.enumerated()
                            .filter { !indices.contains($0.offset) }
                            .map(\.element)
                    }
                }
            }
        }
    }

    private var noteSection: some View {
        Section("Note (optional)") {
            TextField("Any special requests…", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .accessibilityLabel("Note")
        }
    }

    // MARK: - Actions

    private func submit() async {
        guard let cid = Int64(customerId) else {
            errorMessage = "Invalid customer ID"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            let body = WaitlistCreateBody(
                customerId: cid,
                requestedServiceType: serviceType,
                preferredWindows: preferredWindows,
                note: note.isEmpty ? nil : note
            )
            _ = try await api.createWaitlistEntry(body)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func windowLabel(_ w: PreferredWindow) -> String {
        "\(Self.dateFormatter.string(from: w.start)) – \(Self.dateFormatter.string(from: w.end))"
    }
}
