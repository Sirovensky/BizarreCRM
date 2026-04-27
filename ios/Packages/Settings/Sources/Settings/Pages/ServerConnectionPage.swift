import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §19.22 Server connection test page

// MARK: - ViewModel

@MainActor
@Observable
public final class ServerConnectionViewModel: Sendable {
    public enum ConnectionStatus: Sendable {
        case idle
        case testing
        case success(latencyMs: Double, authOk: Bool, certSHA: String?)
        case failed(String)
    }

    public var status: ConnectionStatus = .idle
    public var serverURL: String = ""

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        Task { await loadCurrentURL() }
    }

    func loadCurrentURL() async {
        let url = await api.currentBaseURL()
        serverURL = url?.absoluteString ?? "—"
    }

    public func testConnection() async {
        status = .testing
        guard await api.currentBaseURL() != nil else {
            status = .failed("No server URL configured. Sign in first.")
            return
        }

        let start = Date()
        do {
            // Ping via endpoint wrapper (§20 containment — see ServerConnectionEndpoints.swift)
            let healthy = try await api.healthPing()
            let latencyMs = Date().timeIntervalSince(start) * 1000
            var authOk = false
            if healthy {
                do {
                    authOk = try await api.authMeCheck()
                } catch {
                    authOk = false
                }
            }
            let sha: String? = nil  // Populated by PinnedURLSessionDelegate when SPKI pinning active
            status = .success(latencyMs: latencyMs, authOk: authOk, certSHA: sha)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

/// §19.22 Server connection page — test latency, auth check, cert SHA.
/// Also notes that server URL + username are retained in Keychain (tokens are NOT).
public struct ServerConnectionPage: View {
    @State private var vm: ServerConnectionViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: ServerConnectionViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("Current server") {
                HStack {
                    Text("URL")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(vm.serverURL)
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Server URL: \(vm.serverURL)")

                HStack {
                    Text("Last-used retention")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text("Keychain (tokens excluded)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Section {
                Button {
                    Task { await vm.testConnection() }
                } label: {
                    HStack {
                        if case .testing = vm.status {
                            ProgressView().frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityHidden(true)
                        }
                        Text("Test connection")
                            .foregroundStyle(.bizarreOrange)
                    }
                }
                .disabled({ if case .testing = vm.status { return true }; return false }())
                .accessibilityIdentifier("server.testConnection")
            }

            switch vm.status {
            case .idle:
                EmptyView()
            case .testing:
                EmptyView()
            case .success(let latency, let authOk, let certSHA):
                Section("Connection details") {
                    resultRow(label: "Latency", value: String(format: "%.0f ms", latency), icon: "bolt", success: latency < 500)
                    resultRow(label: "Auth token", value: authOk ? "Valid" : "Expired / missing", icon: "key", success: authOk)
                    if let sha = certSHA {
                        HStack {
                            Text("Cert SHA-256")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text(sha)
                                .font(.brandMono(size: 10))
                                .foregroundStyle(.bizarreOnSurface)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    } else {
                        HStack {
                            Text("SPKI pinning")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text("Not configured (optional)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
            case .failed(let msg):
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                            .accessibilityHidden(true)
                        Text(msg)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Connection failed: \(msg)")
            }
        }
            // §65.1 — Universal Links transparency (agent-9 b5)
            Section {
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    Label("Universal Links", systemImage: "link")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Cloud-hosted tenants (*.bizarrecrm.com) open the app via HTTPS — Apple validates the AASA file once per device.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("Self-hosted tenants use the bizarrecrm:// custom URI scheme instead. Apple entitlements are compiled per-domain, so per-tenant re-signing is not supported.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("Public paths (/public/*) are excluded from the AASA so customers always see the web page, not the app.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .listRowBackground(Color.bizarreSurface1)
            } header: {
                Text("Deep links")
            }
        }
        .navigationTitle("Server Connection")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    @ViewBuilder
    private func resultRow(label: String, value: String, icon: String, success: Bool) -> some View {
        HStack {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(success ? .bizarreSuccess : .bizarreWarning)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value), \(success ? "OK" : "warning")")
    }
}
