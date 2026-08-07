//
//  EntitlementTests.swift
//  FinanceKitSyncTests
//
//  The two decisions that can't be re-made later: who is grandfathered, and
//  what happens to a pending background refresh while StoreKit is still
//  thinking. Neither test touches StoreKit — `Entitlement.fixed` and the pure
//  `backgroundRefreshAction` are the seams that make that possible.
//
import Testing
import Foundation
@testable import FinanceKitSync

@Suite("Grandfathering")
struct GrandfatheringTests {

    @Test("an install from before the paywall is grandfathered")
    func predatesPaywall() {
        // v1.0 shipped as build 19.
        #expect(Entitlement.predatesPaywall(originalAppVersion: "19", firstPaywalledBuild: 20))
        #expect(Entitlement.predatesPaywall(originalAppVersion: "1", firstPaywalledBuild: 20))
    }

    @Test("the first paywalled build, and everything after it, is not")
    func fromThePaywallOnwards() {
        #expect(!Entitlement.predatesPaywall(originalAppVersion: "20", firstPaywalledBuild: 20))
        #expect(!Entitlement.predatesPaywall(originalAppVersion: "21", firstPaywalledBuild: 20))
        #expect(!Entitlement.predatesPaywall(originalAppVersion: "100", firstPaywalledBuild: 20))
    }

    @Test("an unparseable original version is not grandfathered")
    func unparseable() {
        // StoreKit testing and TestFlight report a marketing-style version.
        // Failing closed asks a developer to subscribe; failing open would
        // hand every real user a permanent free entitlement.
        #expect(!Entitlement.predatesPaywall(originalAppVersion: "1.0", firstPaywalledBuild: 20))
        #expect(!Entitlement.predatesPaywall(originalAppVersion: "", firstPaywalledBuild: 20))
    }
}

@Suite("Entitlement status")
@MainActor
struct EntitlementStatusTests {

    @Test("only a resolved 'entitled' permits background sync")
    func permission() {
        #expect(Entitlement.fixed(.entitled(.subscription)).allowsBackgroundSync)
        #expect(Entitlement.fixed(.entitled(.grandfathered)).allowsBackgroundSync)
        #expect(!Entitlement.fixed(.notEntitled).allowsBackgroundSync)
        #expect(!Entitlement.fixed(.unknown).allowsBackgroundSync)
    }

    @Test("'unknown' is not a lapse")
    func unknownIsNotALapse() {
        // The banner and the paywall both hang off `hasLapsed`. If unresolved
        // counted as lapsed, every cold start would flash a paywall at a
        // paying subscriber.
        #expect(!Entitlement.fixed(.unknown).hasLapsed)
        #expect(!Entitlement.fixed(.unknown).isResolved)
        #expect(Entitlement.fixed(.notEntitled).hasLapsed)
    }

    @Test("refresh adopts what the resolver reports")
    func refreshAdopts() async {
        let entitlement = Entitlement(initial: .unknown, resolve: { .entitled(.subscription) })
        #expect(!entitlement.allowsBackgroundSync)

        let resolved = await entitlement.refresh()

        #expect(resolved == .entitled(.subscription))
        #expect(entitlement.status == .entitled(.subscription))
        #expect(entitlement.allowsBackgroundSync)
    }
}

@Suite("Background refresh gating")
struct BackgroundRefreshGatingTests {

    private func action(
        _ status: Entitlement.Status, enabled: Bool = true, configured: Bool = true
    ) -> SyncCoordinator.BackgroundRefreshAction {
        SyncCoordinator.backgroundRefreshAction(
            entitlement: status, backgroundSyncEnabled: enabled, isConfigured: configured
        )
    }

    @Test("a subscriber schedules")
    func entitledSchedules() {
        #expect(action(.entitled(.subscription)) == .schedule)
        #expect(action(.entitled(.grandfathered)) == .schedule)
    }

    @Test("a lapse cancels the pending request")
    func lapseCancels() {
        // Not merely "don't schedule": a request submitted while entitled is
        // still on the books and would keep firing.
        #expect(action(.notEntitled) == .cancel)
    }

    @Test("an unresolved entitlement changes nothing")
    func unknownLeavesItAlone() {
        // At launch StoreKit hasn't answered yet. Cancelling here would drop a
        // paying subscriber's pending refresh on every cold start.
        #expect(action(.unknown) == .leaveAsIs)
    }

    @Test("the toggle and the config still win")
    func togglesWin() {
        #expect(action(.entitled(.subscription), enabled: false) == .cancel)
        #expect(action(.entitled(.subscription), configured: false) == .cancel)
        // Even before StoreKit answers — these need no entitlement to decide.
        #expect(action(.unknown, enabled: false) == .cancel)
    }
}
