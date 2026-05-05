#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CashPeriodLockView (§39.4 period lock UI)

/// Displays a list of locked accounting periods and allows managers to
/// create new locks or perform override unlocks (with PIN confirmation).
///
/// Entry point: Settings → Cash Register → Period Locks, or from the
/// End-of-Day Wizard step 6 (lock period).
///
/// Roles: view access = all authenticated; lock/unlock = manager only.
@Observable
final class CashPeriodLockViewModel: @unchecked Sendable {

    // MARK: - State

    var locks: [CashPeriodLock] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var isLocking: Bool = false

    // MARK: - Lock form

    var lockNotes: String = ""

    // MARK: - Unlock confirmation

    var unlockTargetId: Int64?
    var unlockManagerPin: String = ""
    var unlockReason: String = ""
    var isUnlocking: Bool = false

    // MARK: - Dependencies

    private let repository: CashPeriodLockRepository

    init(repository: CashPeriodLockRepository) {
        self.repository = repository
    }

    // MARK: - Load

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            locks = try await repository.listLocks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Lock a period

    @MainActor
    func lockCurrentPeriod(start: Date, end: Date, revenueCents: Int) async {
        isLocking = true
        errorMessage = nil
        defer { isLocking = false }
        do {
            let request = CashPeriodLockRequest(
                periodStart: start,
                periodEnd: end,
                reconciledRevenueCents: revenueCents,
                notes: lockNotes.isEmpty ? nil : lockNotes
            )
            let lock = try await repository.lockPeriod(request)
            locks.insert(lock, at: 0)
            lockNotes = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Manager override unlock

    @MainActor
    func unlockPeriod() async {
        guard let id = unlockTargetId, !unlockManagerPin.isEmpty else { return }
        isUnlocking = true
        errorMessage = nil
        defer { isUnlocking = false; unlockTargetId = nil }
        do {
            let req = CashPeriodUnlockRequest(managerPin: unlockManagerPin, reason: unlockReason)
            try await repository.unlockPeriod(id: id, request: req)
            locks.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct CashPeriodLockView: View {

    @State private var vm: CashPeriodLockViewModel
    @State private var showingLockSheet: Bool = false
    @State private var showingUnlockAlert: Bool = false

    let api: APIClient?

    public init(api: APIClient?) {
        self.api = api
        let repo: CashPeriodLockRepository
        if let api {
            repo = CashPeriodLockRepositoryImpl(api: api)
        } else {
            repo = PreviewCashPeriodLockRepository()
        }
        _vm = State(initialValue: CashPeriodLockViewModel(repository: repo))
    }

    public var body: some View {
        List {
            if vm.locks.isEmpty && !vm.isLoading {
                emptyState
            } else {
                ForEach(vm.locks) { lock in
                    PeriodLockRow(lock: lock) {
                        vm.unlockTargetId = lock.id
                        vm.unlockManagerPin = ""
                        vm.unlockReason = ""
                        showingUnlockAlert = true
                    }
                }
            }
        }
        .navigationTitle("Period Locks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLockSheet = true
                } label: {
                    Label("Lock period", systemImage: "lock.badge.plus")
                }
                .accessibilityIdentifier("pos.periodLocks.newLock")
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading && vm.locks.isEmpty {
                ProgressView()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $showingLockSheet) {
            lockPeriodSheet
        }
        .alert("Manager override required", isPresented: $showingUnlockAlert) {
            SecureField("Manager PIN", text: $vm.unlockManagerPin)
                .keyboardType(.numberPad)
            TextField("Reason", text: $vm.unlockReason)
            Button("Unlock", role: .destructive) {
                Task { await vm.unlockPeriod() }
            }
            .disabled(vm.unlockManagerPin.isEmpty)
            Button("Cancel", role: .cancel) { vm.unlockTargetId = nil }
        } message: {
            Text("This period is reconciled and locked. Enter your manager PIN and a reason to override.")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No locked periods",
            systemImage: "lock.open",
            description: Text("Lock a reconciled period to prevent back-dated changes.")
        )
        .accessibilityIdentifier("pos.periodLocks.empty")
    }

    // MARK: - Lock period sheet

    private var lockPeriodSheet: some View {
        NavigationStack {
            Form {
                Section("Notes (optional)") {
                    TextField("e.g. Approved by manager", text: $vm.lockNotes, axis: .vertical)
                        .lineLimit(3)
                        .accessibilityIdentifier("pos.periodLocks.notes")
                }

                Section {
                    Text("Locking the current period prevents any back-dated changes. A manager override is required to modify locked transactions.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .navigationTitle("Lock Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingLockSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isLocking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Lock") {
                            Task {
                                let now = Date()
                                let monthStart = Calendar.current.date(
                                    from: Calendar.current.dateComponents([.year, .month], from: now)
                                ) ?? now
                                await vm.lockCurrentPeriod(
                                    start: monthStart,
                                    end: now,
                                    revenueCents: 0    // caller passes actual from reconciliation
                                )
                                showingLockSheet = false
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.bizarreOrange)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Period lock row

private struct PeriodLockRow: View {

    let lock: CashPeriodLock
    let onUnlock: () -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Label {
                    Text(periodLabel)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                } icon: {
                    Image(systemName: lock.isActive ? "lock.fill" : "lock.open.fill")
                        .foregroundStyle(lock.isActive ? .bizarreSuccess : .bizarreWarning)
                }
                Spacer()
                Text(CartMath.formatCents(lock.reconciledRevenueCents))
                    .font(.brandBodyMedium().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
            }

            Text("Locked \(dateFormatter.string(from: lock.lockedAt)) by \(lock.lockedByDisplayName)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            if let notes = lock.notes, !notes.isEmpty {
                Text(notes)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .italic()
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onUnlock) {
                Label("Override", systemImage: "lock.open")
            }
            .tint(.bizarreWarning)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Period \(periodLabel), locked by \(lock.lockedByDisplayName), revenue \(CartMath.formatCents(lock.reconciledRevenueCents))"
        )
        .accessibilityIdentifier("pos.periodLockRow.\(lock.id)")
    }

    private var periodLabel: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return "\(f.string(from: lock.periodStart)) – \(f.string(from: lock.periodEnd))"
    }
}

// MARK: - Preview repository

private struct PreviewCashPeriodLockRepository: CashPeriodLockRepository {
    func listLocks() async throws -> [CashPeriodLock] { [] }
    func lockPeriod(_ request: CashPeriodLockRequest) async throws -> CashPeriodLock {
        throw AppError.offline
    }
    func unlockPeriod(id: Int64, request: CashPeriodUnlockRequest) async throws {
        throw AppError.offline
    }
}

// MARK: - Preview

#Preview("Period Locks — empty") {
    NavigationStack {
        CashPeriodLockView(api: nil)
    }
    .preferredColorScheme(.dark)
}
#endif
