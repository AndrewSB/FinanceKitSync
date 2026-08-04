//
//  HomeView.swift
//  FinanceKitSync
//
import SwiftUI

struct HomeView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                countsSection
                actionSection
                activitySection
            }
            .navigationTitle("FinanceKitSync")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .refreshable {
                await coordinator.syncNow()
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            LabeledContent("Server", value: ServerConfig.displayHost)

            LabeledContent("Last sync") {
                if let date = coordinator.lastSyncDate {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }

            if let error = coordinator.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        } header: {
            Text("Status")
        }
    }

    private var countsSection: some View {
        Section("Mirrored") {
            LabeledContent("Transactions acknowledged", value: "\(coordinator.acknowledgedCount)")
            if coordinator.lastSentCount > 0 {
                LabeledContent("Sent last run", value: "\(coordinator.lastSentCount)")
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task { await coordinator.syncNow() }
            } label: {
                HStack {
                    Text(coordinator.isSyncing ? "Syncing…" : "Sync now")
                    Spacer()
                    if coordinator.isSyncing { ProgressView() }
                }
            }
            .disabled(coordinator.isSyncing)

            if case .syncing(let progress) = coordinator.state {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activitySection: some View {
        Section {
            NavigationLink {
                LogView()
            } label: {
                Label("Activity log", systemImage: "list.bullet.rectangle")
            }
        }
    }
}
