import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Foundation

// MARK: - §19.22 Server (connection) settings page
//
// Inspect + test the tenant server connection.
// No tenant-switch or sign-out buttons — those live in Profile (§19.1).

// MARK: - Connection test result

public enum ConnectionTestResult: Sendable {
    case idle
    case testing
    case success(latencyMs: Int, tlsCN: String?)
    case failure(String)
}

// NOTE: pingHealth() is declared in SettingsPagesEndpoints.swift

// MARK: - ViewModel

@MainActor
@Observable
public final class ServerSettingsViewModel: Sendable {

    public private(set) var baseURL: String
    public private(set) var connectionResult: ConnectionTestResult = .idle

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
        self.baseURL = api?.currentBaseURL()?.absoluteString ?? "Not configured"
    }

    public func testConnection() async {
        guard let api else {
            connectionResult = .failure("API client not configured.")
            return
        }
        connectionResult = .testing
        do {
            let latencyMs = try await api.pingHealth()
            connectionResult = .success(latencyMs: latencyMs, tlsCN: nil)
        } catch {
            connectionResult = .failure(error.localizedDescription)
        }
    }
}

// MARK: - View

public struct ServerSettingsPage: View {
    @State private var vm: ServerSettingsViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: ServerSettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Base URL") {
                    Text(vm.baseURL)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .font(.brandLabelLarge())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityLabel("Base URL: \(vm.baseURL)")
            } footer: {
                Text("This is the URL of your BizarreCRM server. Set at login. Change it by signing out and logging in with a different server URL.")
            }

            Section("Connection test") {
                connectionStatusRow

                Button {
                    Task { await vm.testConnection() }
                } label: {
                    if case .testing = vm.connectionResult {
                        HStack(spacing: BrandSpacing.sm) {
                            ProgressView().accessibilityLabel("Testing connection")
                            Text("Testing…")
                        }
                    } else {
                        Label("Test connection", systemImage: "network")
                    }
                }
                .disabled({ if case .testing = vm.connectionResult { return true }; return false }())
                .accessibilityIdentifier("server.testConnection")
            }

            Section("Sign-out") {
                NavigationLink("Profile & sign-out") {
                    // Profile page owns sign-out per §19.1.
                    Text("Sign out from Settings → Profile.")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .padding()
                        .navigationTitle("Sign out")
                }
                .accessibilityIdentifier("server.profileLink")
            } footer: {
                Text("To change server or tenant, sign out from the Profile page, then sign in with new credentials.")
            }
        }
        .navigationTitle("Server")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        switch vm.connectionResult {
        case .idle:
            LabeledContent("Status") {
                Text("Not tested")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Connection status: not tested")

        case .testing:
            LabeledContent("Status") {
                Text("Testing…")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Connection status: testing")

        case .success(let ms, let cn):
            LabeledContent("Status") {
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                        Text("Connected")
                            .foregroundStyle(.bizarreSuccess)
                    }
                    Text("\(ms) ms")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                    if let cn = cn {
                        Text("TLS: \(cn)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityLabel("Connection status: connected. Latency \(ms) milliseconds.")

        case .failure(let msg):
            LabeledContent("Status") {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreError)
                    Text("Failed")
                        .foregroundStyle(.bizarreError)
                }
            }
            Text(msg)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreError)
                .accessibilityLabel("Error: \(msg)")
        }
    }
}
