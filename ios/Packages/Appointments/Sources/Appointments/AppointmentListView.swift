import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class AppointmentListViewModel {
    public private(set) var items: [Appointment] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do { items = try await api.listAppointments() }
        catch {
            AppLog.ui.error("Appointments load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct AppointmentListView: View {
    @State private var vm: AppointmentListViewModel
    @State private var showingCreate: Bool = false
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: AppointmentListViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Appointments")
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            AppointmentCreateView(api: api)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            PhaseErrorView(message: err) { Task { await vm.load() } }
        } else if vm.items.isEmpty {
            PhaseEmptyView(icon: "calendar", text: "No appointments")
        } else {
            List {
                ForEach(vm.items) { appt in
                    Row(appointment: appt)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private struct Row: View {
        let appointment: Appointment

        var body: some View {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    if let t = appointment.startTime {
                        Text(String(t.prefix(10)))
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurface)
                        if t.count >= 16 {
                            Text(String(t.dropFirst(11).prefix(5)))
                                .font(.brandMono(size: 11))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
                .frame(width: 80, alignment: .leading)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(appointment.title ?? "Appointment")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let customer = appointment.customerName {
                        Text(customer).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let assigned = appointment.assignedName {
                        Text("with \(assigned)").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()

                if let status = appointment.status {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.bizarreOnSurface)
                        .background(Color.bizarreSurface2, in: Capsule())
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
    }
}

// MARK: - Reusable pane helpers

struct PhaseErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
            Text("Something went wrong")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PhaseEmptyView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(text).font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
