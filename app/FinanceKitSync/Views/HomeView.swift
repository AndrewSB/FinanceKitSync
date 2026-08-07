//
//  HomeView.swift
//  FinanceKitSync
//
import SwiftUI

struct HomeView: View {
    @Environment(SyncCoordinator.self) private var coordinator
    @Environment(Entitlement.self) private var entitlement
#if DEBUG
    @State private var showingSettings = ScreenshotMode.showsSettings
    @State private var showingPaywall = ScreenshotMode.showsPaywall
#else
    @State private var showingSettings = false
    @State private var showingPaywall = false
#endif

    var body: some View {
        NavigationStack {
            List {
                backgroundSyncSection
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .refreshable {
                await coordinator.syncNow()
            }
        }
    }

    // MARK: - Sections

    /// Expiry has to be loud. A subscription that lapses turns off a feature
    /// the user set up once and then stopped thinking about — left silent,
    /// they'd find out weeks later, from stale data on their own server.
    @ViewBuilder
    private var backgroundSyncSection: some View {
        if entitlement.hasLapsed && ServerConfig.backgroundSyncEnabled {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Background sync is off", systemImage: "moon.zzz")
                        .font(.headline)
                    Text("New transactions are only sent while the app is open. Pull to refresh, or subscribe to have them sent automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("See subscription options") {
                        showingPaywall = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
        }
    }

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
