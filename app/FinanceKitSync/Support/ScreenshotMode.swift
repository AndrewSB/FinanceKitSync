//
//  ScreenshotMode.swift
//  FinanceKitSync
//
//  Deterministic synthetic state for App Store screenshots.
//
//  The five listing screens can't be captured from a live run: three of them
//  need a configured server, a populated ledger, and a sync in flight, and the
//  only way to get those honestly is to point the app at real transactions —
//  which is exactly what must not end up in a screenshot.
//
//  So instead the app is launched once per screen with
//
//      -FKSScreenshotScene <settled|syncing|connect|onboarding|settings>
//
//  and seeds itself with invented data. Every value below is fabricated; none
//  of it comes from FinanceKit, and no sync ever runs in this mode.
//
//  This whole file — and every call into it — is behind `#if DEBUG`, so it is
//  absent from the Release binary that ships. Screenshots are captured from a
//  Debug simulator build, which renders identically.
//
#if DEBUG
import Foundation

enum ScreenshotMode {
    enum Scene: String {
        /// Step 1 of onboarding: the explainer.
        case onboarding
        /// Step 2 of onboarding, with a connection test already passing.
        case connect
        /// Home, mid-sync.
        case syncing
        /// Home, settled — last sync time and counts.
        case settled
        /// Home with the settings sheet up.
        case settings
        /// Home with the paywall up. The price is invented too: the capture
        /// script launches from `simctl`, with no scheme and so no StoreKit
        /// configuration file, and the real store isn't reachable either.
        case paywall
    }

    /// Invented, and visibly so. `example.com` is reserved by RFC 2606, so this
    /// address can't be mistaken for anyone's real server.
    static let sampleURL = "https://mirror.example.com:8443"
    private static let sampleToken = "screenshot-placeholder-token"

    static let scene: Scene? = {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-FKSScreenshotScene"),
              args.index(after: flag) < args.endIndex else { return nil }
        return Scene(rawValue: args[args.index(after: flag)])
    }()

    static var isActive: Bool { scene != nil }

    /// Where `OnboardingView` should start. Only meaningful while onboarding is
    /// on screen at all.
    static var onboardingStep: Int { scene == .connect ? 1 : 0 }

    /// Whether `HomeView` should come up with the settings sheet presented.
    static var showsSettings: Bool { scene == .settings }

    /// Whether `HomeView` should come up with the paywall presented.
    static var showsPaywall: Bool { scene == .paywall }

    /// Whether the server form should render an already-passed connection test.
    /// No request is made — the listing shouldn't depend on a server being up.
    static var showsPassedConnectionTest: Bool {
        scene == .connect || scene == .settings
    }

    /// Called before the app decides whether to show onboarding, so the config
    /// it reads is already the one this scene wants.
    @MainActor
    static func prepare() {
        guard let scene else { return }

        switch scene {
        case .onboarding, .connect:
            // Onboarding only appears when no server is configured.
            ServerConfig.setBaseURL(nil)
            ServerConfig.setToken(nil)

        case .syncing, .settled, .settings, .paywall:
            ServerConfig.setBaseURL(URL(string: sampleURL))
            ServerConfig.setToken(sampleToken)
            seedLog()
            seedCoordinator(for: scene)
            seedPurchases(for: scene)
        }
    }

    /// The listing shows the paywall as a prospective subscriber sees it —
    /// trial offered, nothing bought — and every other scene as a subscriber
    /// does, so no scene renders the lapsed banner.
    @MainActor
    private static func seedPurchases(for scene: Scene) {
        Entitlement.shared.seedForScreenshots(
            scene == .paywall ? .notEntitled : .entitled(.subscription)
        )
        SubscriptionStore.shared.seedForScreenshots(
            SubscriptionStore.Offer(
                displayPrice: "$2.99", period: "month", introOffer: "3 days free"
            )
        )
    }

    @MainActor
    private static func seedCoordinator(for scene: Scene) {
        let coordinator = SyncCoordinator.shared
        switch scene {
        case .syncing:
            coordinator.seedForScreenshots(
                state: .syncing(progress: "Sending 12 transactions…"),
                lastSyncDate: Date(timeIntervalSinceNow: -6 * 3600),
                lastSentCount: 0,
                acknowledgedCount: 3_835
            )
        default:
            coordinator.seedForScreenshots(
                state: .idle,
                lastSyncDate: Date(timeIntervalSinceNow: -4 * 60),
                lastSentCount: 12,
                acknowledgedCount: 3_847
            )
        }
    }

    @MainActor
    private static func seedLog() {
        let now = Date()
        // Newest last — LogView reads them in order.
        let lines: [(TimeInterval, String)] = [
            (-6 * 3600 - 41, "sync complete — 4 sent, 3835 acknowledged"),
            (-4 * 60 - 52, "reading transactions since 2026-08-05T18:22:07Z"),
            (-4 * 60 - 48, "12 new, 0 corrections"),
            (-4 * 60 - 45, "sending batch 1 of 1"),
            (-4 * 60 - 41, "sync complete — 12 sent, 3847 acknowledged"),
        ]
        LogStore.shared.seedForScreenshots(
            lines.map { LogEntry(date: now.addingTimeInterval($0.0), message: $0.1) }
        )
    }
}
#endif
