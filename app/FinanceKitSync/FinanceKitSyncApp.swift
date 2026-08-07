//
//  FinanceKitSyncApp.swift
//  FinanceKitSync
//
import SwiftUI

@main
struct FinanceKitSyncApp: App {
    @State private var coordinator = SyncCoordinator.shared
    @State private var entitlement = Entitlement.shared
    @State private var subscriptions = SubscriptionStore.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Onboarding is considered done once a server is configured — there's no
    /// separate "seen it" flag to get out of sync with reality.
    @State private var hasCompletedOnboarding = FinanceKitSyncApp.bootstrap()

    /// Runs before the onboarding decision is made, because in screenshot mode
    /// the seeded config is what that decision has to read. Returns whatever
    /// `hasCompletedOnboarding` should start as.
    @MainActor
    private static func bootstrap() -> Bool {
#if DEBUG
        ScreenshotMode.prepare()
#endif
        return ServerConfig.isConfigured
    }

    init() {
        // Must happen before the app finishes launching.
        SyncCoordinator.shared.registerBackgroundTask()
        // Likewise: a transaction approved while the app was closed (a
        // renewal, Ask to Buy, a refund) is delivered to this listener as soon
        // as the process starts, and is lost if nobody is listening.
        SubscriptionStore.shared.startObservingTransactions()
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
            .environment(entitlement)
            .environment(subscriptions)
            .task {
#if DEBUG
                // Screenshot scenes seed both of these; asking StoreKit would
                // overwrite the seed with "no product, not entitled".
                guard !ScreenshotMode.isActive else { return }
#endif
                await entitlement.refresh()
                await subscriptions.load()
            }
            // A lapse found at launch has to close the gate now, not at the
            // next backgrounding — a request submitted while entitled would
            // otherwise still be pending.
            .onChange(of: entitlement.status) { _, _ in
                coordinator.scheduleBackgroundRefresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                coordinator.scheduleBackgroundRefresh()
            }
        }
    }
}
