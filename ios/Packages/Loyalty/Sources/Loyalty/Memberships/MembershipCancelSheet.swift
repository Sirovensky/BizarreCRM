import SwiftUI
import DesignSystem
import Networking

// MARK: - §38.5 Membership cancel / renewal-reminder UI

/// Sheet shown when staff or customer initiates a membership cancellation.
/// Tenant-configurable end-of-period vs immediate cancel policy displayed
/// as an info row.
public struct MembershipCancelSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let membership: Membership
    public let plan: MembershipPlan?
    public var onConfirm: (CancelPolicy) -> Void

    @State private var selectedPolicy: CancelPolicy = .endOfPeriod
    @State private var reason: String = ""

    public enum CancelPolicy: String, CaseIterable, Sendable {
        case endOfPeriod = "End of billing period"
        case immediate   = "Immediately"
    }

    public init(
        membership: Membership,
        plan: MembershipPlan? = nil,
        onConfirm: @escaping (CancelPolicy) -> Void
    ) {
        self.membership = membership
        self.plan = plan
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section {
                        membershipInfoRow
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    Section("Cancellation timing") {
                        Picker("When to cancel", selection: $selectedPolicy) {
                            ForEach(CancelPolicy.allCases, id: \.self) { policy in
                                Text(policy.rawValue).tag(policy)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        .accessibilityLabel("Cancellation timing: \(selectedPolicy.rawValue)")

                        if selectedPolicy == .endOfPeriod, let nextBilling = membership.nextBillingAt {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                    .accessibilityHidden(true)
                                Text("Benefits active through \(nextBilling.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Benefits active through \(nextBilling.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    Section("Reason (optional)") {
                        TextField("Why is this being cancelled?", text: $reason, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityLabel("Cancellation reason")
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    Section {
                        destructiveWarning
                    }
                    .listRowBackground(Color.bizarreError.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Cancel Membership")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel Membership") {
                        onConfirm(selectedPolicy)
                        dismiss()
                    }
                    .foregroundStyle(.bizarreError)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Confirm membership cancellation")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var membershipInfoRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(.bizarreWarning)
                .font(.system(size: 22))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan?.name ?? "Membership")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Status: \(membership.status.rawValue.capitalized)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var destructiveWarning: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(selectedPolicy == .immediate
                 ? "Cancellation is immediate. Benefits end now."
                 : "Benefits continue until the end of the current billing period. No renewal will be processed.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - §38.5 Membership renewal reminder view

/// Shows per-member renewal notification schedule and lets admin
/// view upcoming reminders (30 / 14 / 7 / 1 day before expiry).
public struct MembershipRenewalReminderView: View {
    public let membership: Membership
    public let plan: MembershipPlan?

    public init(membership: Membership, plan: MembershipPlan? = nil) {
        self.membership = membership
        self.plan = plan
    }

    private let reminderOffsetDays: [Int] = [30, 14, 7, 1]

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("RENEWAL REMINDERS")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
                .accessibilityAddTraits(.isHeader)

            if let nextBilling = membership.nextBillingAt {
                ForEach(reminderOffsetDays, id: \.self) { days in
                    if let fireDate = Calendar.current.date(byAdding: .day, value: -days, to: nextBilling) {
                        reminderRow(daysBeforeExpiry: days, fireDate: fireDate)
                    }
                }
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Reminders sent via push, SMS, and email per member preference.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(.top, BrandSpacing.xs)
            } else {
                Text("No renewal date set.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No renewal date set")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func reminderRow(daysBeforeExpiry: Int, fireDate: Date) -> some View {
        let isPast = fireDate < Date()
        return HStack(spacing: BrandSpacing.sm) {
            Image(systemName: isPast ? "checkmark.circle.fill" : "bell.badge")
                .foregroundStyle(isPast ? .bizarreSuccess : .bizarreOrange)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text("\(daysBeforeExpiry) day\(daysBeforeExpiry == 1 ? "" : "s") before renewal")
                .font(.brandBodyMedium())
                .foregroundStyle(isPast ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
            Spacer(minLength: 0)
            Text(fireDate.formatted(date: .abbreviated, time: .omitted))
                .font(.brandLabelLarge())
                .foregroundStyle(isPast ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isPast
                ? "\(daysBeforeExpiry) day reminder sent on \(fireDate.formatted(date: .abbreviated, time: .omitted))"
                : "Reminder scheduled \(daysBeforeExpiry) days before renewal on \(fireDate.formatted(date: .abbreviated, time: .omitted))"
        )
    }
}
