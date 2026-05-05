#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - StoreCreditExpirationSettingsView

/// §40.2 — Admin view to configure the default store-credit expiration period.
///
/// Presents four options (90 / 180 / 365 days / Never). On selection the
/// view POSTs immediately with no explicit "Save" tap — the intent is a
/// radio-style selector, not a form. A progress indicator replaces the check
/// mark during the POST; errors surface inline.
///
/// Accessible both on iPhone (in a Settings list) and iPad (detail column
/// in a NavigationSplitView).
struct StoreCreditExpirationSettingsView: View {

    // MARK: - State

    private enum ViewState: Equatable {
        case idle
        case saving
        case saved
        case failure(String)
    }

    @State private var selectedPeriod: StoreCreditPolicyRequest.ExpirationPeriod = .days365
    @State private var viewState: ViewState = .idle

    let api: APIClient

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                ForEach(StoreCreditPolicyRequest.ExpirationPeriod.allCases, id: \.self) { period in
                    periodRow(period)
                }
            } header: {
                Text("Store Credit Expiration")
            } footer: {
                Text("New store-credit issuances will expire after this period. Existing balances are unaffected.")
                    .font(.brandLabelSmall())
            }

            if case .failure(let msg) = viewState {
                Section {
                    Text(msg)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                }
            }
            if case .saved = viewState {
                Section {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreSuccess)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Store Credit Expiry")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Period row

    @ViewBuilder
    private func periodRow(_ period: StoreCreditPolicyRequest.ExpirationPeriod) -> some View {
        Button {
            guard period != selectedPeriod else { return }
            selectedPeriod = period
            Task { await savePeriod(period) }
        } label: {
            HStack {
                Text(period.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if viewState == .saving && period == selectedPeriod {
                    ProgressView()
                        .tint(.bizarreOrange)
                } else if period == selectedPeriod {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Selected")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("storeCreditExpiry.\(period.rawValue)")
        .accessibilityLabel(period.displayName)
        .accessibilityAddTraits(period == selectedPeriod ? [.isSelected] : [])
    }

    // MARK: - Save

    private func savePeriod(_ period: StoreCreditPolicyRequest.ExpirationPeriod) async {
        viewState = .saving
        do {
            _ = try await api.updateStoreCreditPolicy(
                StoreCreditPolicyRequest(expirationPeriod: period)
            )
            viewState = .saved
        } catch let APITransportError.httpStatus(code, message) {
            let msg = (message?.isEmpty == false) ? message! : "Save failed"
            viewState = .failure("Save failed (\(code)): \(msg)")
        } catch {
            viewState = .failure("Save failed: \(error.localizedDescription)")
        }
    }
}
#endif
