#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.3 — "Hold cart" sheet. Staff enter an optional note, tap Save, and
/// the cart is serialised to `POST /pos/holds`. On success `cart.markHeld`
/// is called, `onSaved` fires with the server-assigned hold id, and the
/// caller is responsible for dismissing + showing a toast.
///
/// 404/501 fallback: matches the §16.9 refund pattern — shows a
/// "Coming soon" banner in the sheet body rather than crashing.
struct PosHoldCartSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cart: Cart
    let api: APIClient?
    /// Called on successful save. Caller dismisses + shows toast.
    let onSaved: (Int64) -> Void

    @State private var vm: PosHoldCartViewModel

    init(cart: Cart, api: APIClient?, onSaved: @escaping (Int64) -> Void) {
        self.cart = cart
        self.api = api
        self.onSaved = onSaved
        _vm = State(wrappedValue: PosHoldCartViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Summary") {
                        LabeledContent("Items", value: "\(cart.lineCount)")
                        LabeledContent("Total") {
                            Text(CartMath.formatCents(cart.totalCents))
                                .monospacedDigit()
                                .font(.brandBodyLarge())
                        }
                    }

                    Section {
                        TextField("Note (optional)", text: $vm.note, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("pos.holdCart.note")
                    } header: {
                        Text("Note")
                    } footer: {
                        Text("Shown in the holds list so staff can identify this cart.")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }

                    statusSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Hold Cart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .saving = vm.status {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await vm.save(cart: cart) }
                        }
                        .fontWeight(.semibold)
                        .disabled(!vm.canSave)
                        .accessibilityIdentifier("pos.holdCart.save")
                    }
                }
            }
            .onChange(of: vm.status) { _, new in
                if case .saved(let id) = new {
                    let trimmed = vm.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    cart.markHeld(id: id, note: trimmed.isEmpty ? nil : trimmed)
                    onSaved(id)
                }
            }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var statusSection: some View {
        switch vm.status {
        case .idle, .saving:
            EmptyView()
        case .saved:
            EmptyView()
        case .failed(let message):
            Section {
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("pos.holdCart.error")
            }
        case .unavailable(let message):
            Section {
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreWarning)
                    .accessibilityIdentifier("pos.holdCart.unavailable")
            }
        }
    }
}

// MARK: - View model

@MainActor
@Observable
final class PosHoldCartViewModel {
    enum Status: Equatable {
        case idle
        case saving
        case saved(Int64)
        case failed(String)
        case unavailable(String)
    }

    var note: String = ""
    private(set) var status: Status = .idle

    @ObservationIgnored private let api: APIClient?

    init(api: APIClient?) {
        self.api = api
    }

    var canSave: Bool {
        if case .saving = status { return false }
        return true
    }

    func save(cart: Cart) async {
        guard let api else {
            status = .unavailable("Coming soon — server endpoint pending.")
            return
        }
        status = .saving
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        // Serialise the CartSnapshot to JSON for the server's cart_json field.
        let snapshot = CartSnapshot.from(cart: cart)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let cartJsonString: String
        do {
            let data = try encoder.encode(snapshot)
            cartJsonString = String(decoding: data, as: UTF8.self)
        } catch {
            status = .failed("Could not serialise cart: \(error.localizedDescription)")
            return
        }

        let request = CreateHeldCartRequest(
            cartJson: cartJsonString,
            label: trimmedNote.isEmpty ? nil : trimmedNote,
            customerId: cart.customer?.id,
            totalCents: cart.totalCents
        )
        do {
            let row = try await api.createHeldCart(request)
            status = .saved(row.id)
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            status = .unavailable("Coming soon — server endpoint pending.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
#endif
