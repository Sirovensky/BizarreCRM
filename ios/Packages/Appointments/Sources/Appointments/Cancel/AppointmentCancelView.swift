import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentCancelView

/// Confirmation sheet for cancelling an appointment.
///
/// iPhone + iPad: `.presentationDetents([.medium])` sheet with:
///   - "Notify customer?" toggle (fires SMS on confirm)
///   - Optional cancellation reason text field
///   - Destructive "Cancel appointment" button
///   - "Keep appointment" dismiss button
public struct AppointmentCancelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AppointmentCancelViewModel

    private let onCancelled: () -> Void

    public init(appointment: Appointment, api: APIClient, onCancelled: @escaping () -> Void) {
        _vm = State(wrappedValue: AppointmentCancelViewModel(appointment: appointment, api: api))
        self.onCancelled = onCancelled
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.lg) {
                        warningHeader
                        appointmentCard
                        notifyToggle
                        reasonField
                        if let err = vm.errorMessage {
                            errorBanner(err)
                        }
                        actionButtons
                    }
                    .padding(BrandSpacing.md)
                }
            }
            .navigationTitle("Cancel Appointment")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep") { dismiss() }
                        .accessibilityLabel("Keep appointment — do not cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)  // Liquid Glass
        .onChange(of: vm.cancelled) { _, wasCancelled in
            if wasCancelled {
                onCancelled()
                dismiss()
            }
        }
    }

    // MARK: - Sub-views

    private var warningHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Cancel this appointment?")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("This action cannot be undone.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cancel this appointment? This action cannot be undone.")
    }

    private var appointmentCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            if let title = vm.appointment.title {
                Text(title)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            if let customer = vm.appointment.customerName {
                Label(customer, systemImage: "person")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let raw = vm.appointment.startTime {
                Label(formattedDate(raw), systemImage: "calendar")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let assigned = vm.appointment.assignedName {
                Label("with \(assigned)", systemImage: "person.badge.key")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var notifyToggle: some View {
        Toggle(isOn: $vm.notifyCustomer) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Notify customer")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Send cancellation SMS to the customer")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .tint(.bizarreOrange)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Notify customer via SMS when cancelled: \(vm.notifyCustomer ? "on" : "off")")
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Reason (optional)")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("Why is this appointment being cancelled?",
                      text: $vm.cancelReason,
                      axis: .vertical)
                .lineLimit(2...4)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Cancellation reason")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreError)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Error: \(message)")
    }

    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.sm) {
            Button {
                Task { await vm.cancel() }
            } label: {
                if vm.isCancelling {
                    HStack(spacing: BrandSpacing.sm) {
                        ProgressView().tint(.white).accessibilityHidden(true)
                        Text("Cancelling…").foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Cancel Appointment")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreError)
            .disabled(vm.isCancelling)
            .accessibilityLabel(vm.isCancelling ? "Cancelling appointment" : "Confirm appointment cancellation")

            Button("Keep Appointment") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .accessibilityLabel("Keep the appointment — go back")
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw)
            ?? {
                let f = ISO8601DateFormatter()
                return f.date(from: raw)
            }()
            ?? {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                f.timeZone = TimeZone(identifier: "UTC")
                f.locale = Locale(identifier: "en_US_POSIX")
                return f.date(from: raw)
            }()
        guard let date else { return String(raw.prefix(16)) }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
