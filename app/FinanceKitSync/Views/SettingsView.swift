//
//  SettingsView.swift
//  FinanceKitSync
//
import SwiftUI

struct SettingsView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ServerConfig.baseURLString
    @State private var tokenText = ServerConfig.token ?? ""
    @State private var backgroundSync = ServerConfig.backgroundSyncEnabled
    @State private var confirmingResend = false

    var body: some View {
        NavigationStack {
            Form {
                ServerFormView(urlText: $urlText, tokenText: $tokenText)

                Section {
                    Toggle("Background sync", isOn: $backgroundSync)
                        .onChange(of: backgroundSync) { _, newValue in
                            ServerConfig.backgroundSyncEnabled = newValue
                            if newValue { coordinator.scheduleBackgroundRefresh() }
                        }
                } footer: {
                    Text("iOS decides when background syncs actually run, so this isn't instant. Open the app and pull to refresh when you want an immediate sync.")
                }

                Section {
                    Button("Re-send everything", role: .destructive) {
                        confirmingResend = true
                    }
                } footer: {
                    Text("Forgets what the server has already acknowledged, so the next sync replays your full history. Useful after rebuilding the server. Nothing is deleted from your device.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Activity log", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(ServerConfig.validate(urlText) == nil
                                  || tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Replay your full history on the next sync?",
                isPresented: $confirmingResend,
                titleVisibility: .visible
            ) {
                Button("Re-send everything", role: .destructive) {
                    coordinator.resendEverything()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard let url = ServerConfig.validate(urlText) else { return }
        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressChanged = url != ServerConfig.baseURL

        ServerConfig.setBaseURL(url)
        ServerConfig.setToken(token)

        // A new server has acknowledged nothing, so keeping the old ledger
        // would silently withhold the entire history from it.
        if addressChanged {
            coordinator.resendEverything()
        }
        dismiss()
    }
}

extension Bundle {
    var shortVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
