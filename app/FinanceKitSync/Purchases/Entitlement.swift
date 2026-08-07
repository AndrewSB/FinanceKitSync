//
//  Entitlement.swift
//  FinanceKitSync
//
//  The single answer to "may this install sync in the background?".
//
//  `Transaction.currentEntitlements` is read here and nowhere else. Views ask
//  this object; they never ask StoreKit. The failure mode that buys is
//  entitlement checks scattered across the UI that disagree with each other —
//  most visibly on cold start, before StoreKit has answered, when the honest
//  state is "don't know yet" rather than "not entitled". That third state is
//  `.unknown`, and it is why a paying subscriber never sees a paywall flash.
//
import Foundation
import StoreKit

@MainActor
@Observable
final class Entitlement {

    enum Reason: Equatable {
        /// An active (or trialling) subscription.
        case subscription
        /// Installed before the paywall existed. Permanent, never re-evaluated.
        case grandfathered
    }

    enum Status: Equatable {
        /// StoreKit hasn't answered yet. Not the same as "not entitled":
        /// nothing should be taken away, and no paywall should be shown.
        case unknown
        case entitled(Reason)
        case notEntitled
    }

    /// The subscription that unlocks background sync.
    static let productID = "com.asb.FinanceKitSync.monthly"

    /// The first build that shipped the paywall. Anyone whose *original*
    /// download predates it keeps background sync for free, forever.
    ///
    /// v1.0 shipped as build 19 (Xcode Cloud numbers builds; see
    /// `ci_scripts/ci_pre_xcodebuild.sh`), so 20 is the first build that can
    /// possibly carry v1.1. If v1.1 ends up as a higher build number, this
    /// still works — the comparison is "originally downloaded before the
    /// paywall", and every pre-paywall build is below 20.
    nonisolated static let firstPaywalledBuild = 20

    private static let grandfatheredKey = "entitlement_grandfathered"

    static let shared = Entitlement()

    private(set) var status: Status = .unknown

    /// Resolves the current status. Injected so tests — and the sync suite in
    /// particular — never touch StoreKit.
    private let resolve: @MainActor () async -> Status

    init(
        initial: Status = .unknown,
        resolve: @escaping @MainActor () async -> Status = Entitlement.resolveFromStoreKit
    ) {
        self.status = initial
        self.resolve = resolve
    }

    /// A stub that always answers the same thing. Tests only.
    static func fixed(_ status: Status) -> Entitlement {
        Entitlement(initial: status, resolve: { status })
    }

    // MARK: - Questions the rest of the app is allowed to ask

    /// The only question that gates anything. `.unknown` is deliberately not
    /// permission: an unresolved status must never *start* background work,
    /// but it must never cancel it either — see `SyncCoordinator`.
    var allowsBackgroundSync: Bool {
        if case .entitled = status { return true }
        return false
    }

    /// True only once StoreKit has actually said no. Drives the Home banner.
    var hasLapsed: Bool { status == .notEntitled }

    var isResolved: Bool { status != .unknown }

    var isGrandfathered: Bool { status == .entitled(.grandfathered) }

    // MARK: - Refresh

    @discardableResult
    func refresh() async -> Status {
        let resolved = await resolve()
        if resolved != status {
            Log.append("entitlement: \(Self.describe(resolved))")
            status = resolved
        }
        return resolved
    }

    static func describe(_ status: Status) -> String {
        switch status {
        case .unknown: "unresolved"
        case .entitled(.subscription): "subscribed"
        case .entitled(.grandfathered): "grandfathered (installed before the paywall)"
        case .notEntitled: "no subscription"
        }
    }

    // MARK: - StoreKit

    /// Subscription first, grandfathering second: a grandfathered user who
    /// subscribes anyway should read as a subscriber.
    static func resolveFromStoreKit() async -> Status {
        if await hasActiveSubscription() { return .entitled(.subscription) }
        if await isGrandfathered() { return .entitled(.grandfathered) }
        return .notEntitled
    }

    private static func hasActiveSubscription() async -> Bool {
        // `currentEntitlements` already excludes expired and revoked
        // transactions, and is served from the on-device cache, so this
        // answers correctly with no network — which matters, because the
        // background task re-checks it before every run.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == productID, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    // MARK: - Grandfathering

    /// Whether this install predates the paywall.
    ///
    /// Decided once and then frozen: `AppTransaction.originalAppVersion` is
    /// signed by Apple (so reinstalling can't forge it), but the answer is
    /// only interesting on the first launch of the first paywalled build. It
    /// is cached so a later StoreKit hiccup can't quietly revoke it.
    static func isGrandfathered() async -> Bool {
        if let cached = UserDefaults.standard.object(forKey: grandfatheredKey) as? Bool {
            return cached
        }
        guard let originalVersion = await originalAppVersion() else {
            // Couldn't ask — no cached AppTransaction and no network. Don't
            // write an answer we aren't sure of; try again next launch.
            return false
        }
        let grandfathered = predatesPaywall(originalAppVersion: originalVersion)
        UserDefaults.standard.set(grandfathered, forKey: grandfatheredKey)
        Log.append(
            "original download was build \(originalVersion) — "
            + (grandfathered ? "grandfathered" : "paywalled")
        )
        return grandfathered
    }

    private static func originalAppVersion() async -> String? {
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let appTransaction) = result else { return nil }
            return appTransaction.originalAppVersion
        } catch {
            return nil
        }
    }

    /// On iOS `originalAppVersion` is the *build* number (`CFBundleVersion`),
    /// not the marketing version.
    ///
    /// Anything unparseable is treated as "not grandfathered". That covers the
    /// StoreKit-testing and TestFlight environments, which report "1.0" — a
    /// developer or beta tester being asked to subscribe is the harmless
    /// direction to be wrong in, and the alternative (parse failure ⇒ free
    /// forever) would hand every real user a permanent entitlement.
    nonisolated static func predatesPaywall(
        originalAppVersion: String, firstPaywalledBuild: Int = Entitlement.firstPaywalledBuild
    ) -> Bool {
        guard let build = Int(originalAppVersion) else { return false }
        return build < firstPaywalledBuild
    }

#if DEBUG
    /// Screenshot mode only — see `ScreenshotMode`.
    func seedForScreenshots(_ status: Status) {
        self.status = status
    }
#endif
}
