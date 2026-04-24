import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
#endif

/// §9 Phase 4 Lead detail — fetches `/leads/{id}` on mount and renders the
/// deep record: header + contact + pipeline status + attached devices +
/// scheduled appointments. Edit and Convert actions wired in Phase 4.
@MainActor
@Observable
public final class LeadDetailViewModel {
    public enum State: Sendable {
        case loading
        case loaded(LeadDetail)
        case failed(String)
    }

    public var state: State = .loading

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let id: Int64

    public init(api: APIClient, id: Int64) {
        self.api = api
        self.id = id
    }

    public func load() async {
        if case .loaded = state { /* soft refresh — keep stale rows visible */ } else {
            state = .loading
        }
        do {
            let detail = try await api.getLead(id: id)
            state = .loaded(detail)
        } catch {
            AppLog.ui.error("Lead detail load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

public struct LeadDetailView: View {
    @State private var vm: LeadDetailViewModel
    /// API client kept so Edit / Convert sheets can init their own VMs.
    private let api: APIClient
    @State private var showingEdit = false
    @State private var showingConvert = false

    public init(api: APIClient, id: Int64) {
        self.api = api
        _vm = State(wrappedValue: LeadDetailViewModel(api: api, id: id))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(title)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { detailToolbar }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showingEdit) {
            if case .loaded(let detail) = vm.state {
                LeadEditView(api: api, lead: detail) { updated in
                    vm.state = .loaded(updated)
                }
            }
        }
        .sheet(isPresented: $showingConvert) {
            if case .loaded(let detail) = vm.state {
                LeadConvertSheet(api: api, lead: detail) { _, _ in
                    // Reload so status chip shows 'converted'.
                    Task { await vm.load() }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if case .loaded(let detail) = vm.state {
                // Only show Convert if not already converted / lost.
                if detail.status != "converted" && detail.status != "lost" {
                    Button {
                        showingConvert = true
                    } label: {
                        Label("Convert", systemImage: "arrow.right.circle")
                    }
                    .accessibilityLabel("Convert lead to ticket")
                }
                Button {
                    showingEdit = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .accessibilityLabel("Edit lead")
                #if canImport(UIKit)
                .keyboardShortcut("e", modifiers: .command)
                #endif
            }
        }
    }

    private var title: String {
        if case .loaded(let d) = vm.state { return d.displayName }
        return "Lead"
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load lead")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let detail):
            loadedBody(detail)
        }
    }

    @ViewBuilder
    private func loadedBody(_ detail: LeadDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                headerCard(detail)
                if hasContact(detail) { contactCard(detail) }
                if let notes = detail.notes, !notes.isEmpty { notesCard(notes) }
                if !detail.devices.isEmpty { devicesCard(detail.devices) }
                if !detail.appointments.isEmpty { appointmentsCard(detail.appointments) }
                metaCard(detail)
            }
            .padding(BrandSpacing.base)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headerCard(_ detail: LeadDetail) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.displayName)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: BrandSpacing.sm)
                if let score = detail.leadScore {
                    scoreBadge(score)
                }
            }
            HStack(spacing: BrandSpacing.xs) {
                if let status = detail.status, !status.isEmpty {
                    statusChip(status)
                }
                if let source = detail.source, !source.isEmpty {
                    Text(source.capitalized)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xxs)
                        .background(Color.bizarreSurface2, in: Capsule())
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func statusChip(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOnOrange)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Color.bizarreOrange, in: Capsule())
            .accessibilityLabel("Pipeline status \(status.capitalized)")
    }

    private func scoreBadge(_ score: Int) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(score)")
                .font(.brandTitleLarge())
                .foregroundStyle(score >= 70 ? .bizarreSuccess : .bizarreOnSurface)
                .monospacedDigit()
            Text("of 100")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lead score \(score) of 100")
    }

    private func hasContact(_ d: LeadDetail) -> Bool {
        (d.email?.isEmpty == false) || (d.phone?.isEmpty == false)
    }

    private func contactCard(_ detail: LeadDetail) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Contact")
            if let phone = detail.phone, !phone.isEmpty {
                contactRow(icon: "phone.fill", text: PhoneFormatter.format(phone), action: { tel(phone) })
            }
            if let email = detail.email, !email.isEmpty {
                contactRow(icon: "envelope.fill", text: email, action: { mailto(email) })
            }
            if let customer = detail.customerDisplayName {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text("Linked customer")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer(minLength: BrandSpacing.sm)
                    Text(customer)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func contactRow(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .lineLimit(1)
                Spacer(minLength: BrandSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
        .accessibilityLabel(text)
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Notes")
            Text(notes)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func devicesCard(_ devices: [LeadDevice]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Devices (\(devices.count))")
            VStack(spacing: 0) {
                ForEach(Array(devices.enumerated()), id: \.element.id) { idx, device in
                    LeadDeviceRow(device: device)
                    if idx < devices.count - 1 {
                        Divider().overlay(Color.bizarreOutline.opacity(0.25))
                    }
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func appointmentsCard(_ appointments: [LeadAppointment]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Appointments (\(appointments.count))")
            VStack(spacing: 0) {
                ForEach(Array(appointments.enumerated()), id: \.element.id) { idx, appt in
                    LeadAppointmentRow(appointment: appt)
                    if idx < appointments.count - 1 {
                        Divider().overlay(Color.bizarreOutline.opacity(0.25))
                    }
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func metaCard(_ detail: LeadDetail) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Meta")
            if let assigned = detail.assignedDisplayName {
                metaRow(label: "Assigned to", value: assigned)
            }
            if let created = detail.createdAt {
                metaRow(label: "Created", value: created)
            }
            if let updated = detail.updatedAt, updated != detail.createdAt {
                metaRow(label: "Last updated", value: updated)
            }
            metaRow(label: "Lead ID", value: "#\(detail.id)")
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer(minLength: BrandSpacing.sm)
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .tracking(0.8)
    }

    // MARK: - Actions

    private func tel(_ phone: String) {
        #if canImport(UIKit)
        let cleaned = phone.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel:\(cleaned)") else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func mailto(_ email: String) {
        #if canImport(UIKit)
        guard let url = URL(string: "mailto:\(email)") else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

private struct LeadDeviceRow: View {
    let device: LeadDevice

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "iphone")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                // Show repair type as subtitle when present
                if let repair = device.repairType, !repair.isEmpty {
                    Text(repair.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                // Show problem description
                if let problem = device.problem, !problem.isEmpty {
                    Text(problem)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            if let price = device.price {
                Text(currency(price))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

private struct LeadAppointmentRow: View {
    let appointment: LeadAppointment

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "calendar")
                .foregroundStyle(.bizarreOrange)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(appointment.title ?? "Appointment #\(appointment.id)")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let start = appointment.startTime {
                    Text(start)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                if let location = appointment.location, !location.isEmpty {
                    Text(location)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            if let status = appointment.status {
                Text(status.capitalized)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreSurface2, in: Capsule())
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}
