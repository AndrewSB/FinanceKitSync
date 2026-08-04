//
//  FinanceKitSyncApp.swift
//  FinanceKitSync
//
import SwiftUI

@main
struct FinanceKitSyncApp: App {
    @State private var coordinator = SyncCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Onboarding is considered done once a server is configured — there's no
    /// separate "seen it" flag to get out of sync with reality.
    @State private var hasCompletedOnboarding = ServerConfig.isConfigured

    init() {
        // Must happen before the app finishes launching.
        SyncCoordinator.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    HomeView()
                } else {
                    OnboardingView(onComplete: { hasCompletedOnboarding = true })
                }
            }
            .environment(coordinator)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                coordinator.scheduleBackgroundRefresh()
            }
        }
    }
}
