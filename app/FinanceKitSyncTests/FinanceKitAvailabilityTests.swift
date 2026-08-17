//
//  FinanceKitAvailabilityTests.swift
//  FinanceKitSyncTests
//
//  Pins down FinanceKit's behaviour in the simulator, because it is not what
//  the API surface suggests.
//
//  MEASURED, 2026-08-04, iPhone 17 Pro simulator, iOS 27:
//
//    FinanceStore.isDataAvailable(.financialData)  ->  true
//    FinanceStore.shared.accounts(query:)          ->  TRAPS
//
//        FinanceKit/FinanceDataStore.swift:53: Fatal error: Could not create
//        CoreDataStore: Error Domain=NSCocoaErrorDomain Code=134070
//        "An error occurred in the persistent store."
//        UserInfo={Problem=request failed, insufficient permission}
//
//  So the availability check is actively misleading in the simulator, and the
//  trap can't be caught. SyncEngine therefore returns .skipped on simulator
//  before touching FinanceKit at all. There is deliberately NO test here that
//  calls into FinanceStore — such a test kills the whole test run.
//
import Testing
import Foundation
import FinanceKit
@testable import FinanceKitSync

@Suite("FinanceKit availability")
struct FinanceKitAvailabilityTests {

    @Test("isDataAvailable is not trustworthy on its own in the simulator")
    func availabilityIsMisleading() {
        #if targetEnvironment(simulator)
        // If this ever starts returning false, the simulator has gained a real
        // FinanceKit store (or Apple fixed the reporting) and SyncEngine's
        // unconditional simulator bail-out could be relaxed.
        #expect(FinanceStore.isDataAvailable(.financialData),
                "simulator no longer reports financial data as available — revisit SyncEngine's simulator guard")
        #endif
    }

    @Test("a sync in the simulator is skipped rather than crashing")
    func simulatorSkips() async {
        // The regression guard for the crash: before the fix, this call reached
        // FinanceStore and took the entire test process down with it.
        await ConfigIsolation.withConfig(
            url: URL(string: "https://unused.invalid")!, token: "unused"
        ) {
            // Assert the precondition separately. Without this, a failed
            // Keychain write shows up as ".notConfigured" and reads like the
            // simulator guard is broken, which is a slow thing to diagnose.
            #expect(ServerConfig.baseURL != nil, "base URL did not persist")
            #expect(ServerConfig.token == "unused", "token did not persist to the Keychain")

            #if targetEnvironment(simulator)
            let outcome = await SyncEngine.run(log: { _ in })
            guard case .skipped = outcome else {
                Issue.record("expected .skipped in the simulator, got \(outcome)")
                return
            }
            #endif
        }
    }

    @Test("a sync with no server configured stops before touching FinanceKit")
    func notConfiguredShortCircuits() async {
        // Guards the ordering in SyncEngine.run: the configuration check comes
        // first, so an unconfigured app never reaches a FinanceKit query.
        await ConfigIsolation.withConfig(url: nil, token: nil) {
            guard case .notConfigured = await SyncEngine.run(log: { _ in }) else {
                Issue.record("expected .notConfigured")
                return
            }
        }
    }

    @Test("the local viewer fails safely in the simulator")
    func localViewerSkipsFinanceKit() async {
        #if targetEnvironment(simulator)
        do {
            _ = try await SyncEngine.loadLocalSnapshot()
            Issue.record("expected the local viewer to reject the simulator")
        } catch {
            #expect(error.localizedDescription.contains("physical device"))
        }
        #endif
    }
}
