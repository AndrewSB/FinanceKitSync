//
//  DemoModeTests.swift
//  FinanceKitSyncTests
//
//  The demo is what App Review uses to exercise the app, so it has to work
//  in the simulator with no server and no FinanceKit — the same conditions
//  these tests run under.
//
import Testing
import Foundation
@testable import FinanceKitSync

@Suite("Demo mode")
struct DemoModeTests {

    /// Runs `body` in demo mode with the real config parked at `url`/`token`,
    /// and leaves the demo before the config lock is released — a deferred
    /// leave could otherwise land after the next test has set its own config.
    private func inDemo<T>(
        url: URL? = nil, token: String? = nil, _ body: () async throws -> T
    ) async throws -> T {
        try await ConfigIsolation.withConfig(url: url, token: token) {
            await MainActor.run { DemoMode.shared.enter() }
            let result: Result<T, Error>
            do { result = .success(try await body()) } catch { result = .failure(error) }
            await MainActor.run { DemoMode.shared.leave() }
            return try result.get()
        }
    }

    @Test("the sample dataset is stable from one process to the next")
    func datasetIsDeterministic() {
        // Hashes and ids must not depend on "now", or the ledger would think
        // every row changed on every launch and re-send the whole history.
        let first = DemoDataset.entries
        let second = DemoDataset.entries
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.hash) == second.map(\.hash))
        #expect(Set(first.map(\.id)).count == first.count, "ids must be unique")
        #expect(first.count > 50, "enough rows to look like a real history")
        #expect(first.first!.date <= first.last!.date, "oldest first, like FinanceKit")
        // Ids look like the UUIDs FinanceKit hands out.
        #expect(first.allSatisfy { UUID(uuidString: $0.id) != nil })
        #expect(DemoDataset.syncAccounts.allSatisfy { UUID(uuidString: $0.id) != nil })
    }

    @Test("every sample transaction belongs to a sample account")
    func transactionsReferenceAccounts() {
        let accountIds = Set(DemoDataset.syncAccounts.map(\.id))
        for entry in DemoDataset.entries {
            #expect(accountIds.contains(entry.packet.accountId))
        }
    }

    @Test("the demo server answers the connection check")
    func demoServerPassesHealthCheck() async {
        let url = DemoMode.serverURL
        let ok = await SyncAPI.checkHealth(
            baseURL: url, token: DemoMode.token, session: DemoMode.session(for: url)
        )
        #expect(ok == .ok)

        let bad = await SyncAPI.checkHealth(
            baseURL: url, token: "wrong", session: DemoMode.session(for: url)
        )
        #expect(bad == .unauthorized)
    }

    @Test("only the demo address is routed to the demo server")
    func onlyDemoURLIsIntercepted() {
        #expect(DemoMode.isDemoURL(DemoMode.serverURL))
        #expect(!DemoMode.isDemoURL(URL(string: "https://box.example.ts.net:8443")!))
        #expect(DemoMode.session(for: URL(string: "https://example.com")!) === URLSession.shared)
    }

    @Test("a full demo sync sends the dataset once, then nothing")
    func demoSyncRoundTrips() async throws {
        try await inDemo {
            // Start from a clean demo ledger, whatever an earlier run left.
            try SyncLedger.open()?.reset()
            DemoServer.reset()

            guard case .success(let sent) = await SyncEngine.run(log: { _ in }) else {
                Issue.record("first demo run should succeed")
                return
            }
            #expect(sent == DemoDataset.entries.count)
            #expect(DemoServer.transactionCount == DemoDataset.entries.count)
            #expect(SyncLedger.open()?.count() == DemoDataset.entries.count)

            guard case .success(let again) = await SyncEngine.run(log: { _ in }) else {
                Issue.record("second demo run should succeed")
                return
            }
            #expect(again == 0, "everything was already acknowledged")
        }
    }

    @Test("the local records browser reads the dataset in demo mode")
    func snapshotComesFromDataset() async throws {
        try await inDemo {
            let snapshot = try await SyncEngine.loadLocalSnapshot()
            #expect(snapshot.accounts.count == DemoDataset.syncAccounts.count)
            #expect(snapshot.transactions.count == DemoDataset.entries.count)
        }
    }

    @Test("leaving the demo restores the real server address")
    func leaveRestoresConfig() async throws {
        let real = URL(string: "https://box.example.ts.net:8443")!
        try await ConfigIsolation.withConfig(url: real, token: "real-token") {
            await MainActor.run { DemoMode.shared.enter() }
            #expect(ServerConfig.baseURL == DemoMode.serverURL)
            #expect(ServerConfig.token == DemoMode.token)
            #expect(ServerConfig.isConfigured)

            await MainActor.run { DemoMode.shared.leave() }
            #expect(ServerConfig.baseURL == real)
            #expect(ServerConfig.token == "real-token")
        }
    }
}
