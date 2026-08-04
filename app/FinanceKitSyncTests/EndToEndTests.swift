//
//  EndToEndTests.swift
//  FinanceKitSyncTests
//
//  Drives the real SyncEngine against a real server. Opt-in: skipped unless
//  FKS_TEST_URL and FKS_TEST_TOKEN are set, so no credentials live in the repo
//  and CI doesn't depend on a reachable host.
//
//      FKS_TEST_URL=https://box.example.ts.net:8443 \
//      FKS_TEST_TOKEN=... \
//      xcodebuild test -scheme FinanceKitSync -destination '...'
//
//  What this DOES prove, against the real server over real TLS: packet
//  encoding, bearer auth, transport, the server's idempotent upsert, correction
//  handling, and receipt decoding.
//
//  What it CANNOT prove: anything downstream of a FinanceKit read. FinanceKit
//  is unavailable in the simulator — worse, it *traps* rather than throwing
//  (see FinanceKitAvailabilityTests) — so SyncEngine bails out early there.
//  The read, the mapping, pagination, and batching are only exercisable on a
//  physical device with an approved entitlement. See docs/workstream-app.md.
//
import Testing
import Foundation
@testable import FinanceKitSync

private struct TestServer {
    let url: URL
    let token: String

    /// nil when the environment isn't configured, which skips the suite.
    static func fromEnvironment() -> TestServer? {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["FKS_TEST_URL"], let url = ServerConfig.validate(raw),
              let token = env["FKS_TEST_TOKEN"], !token.isEmpty else {
            return nil
        }
        return TestServer(url: url, token: token)
    }
}

@Suite("End to end", .serialized,
       .enabled(if: TestServer.fromEnvironment() != nil,
                "set FKS_TEST_URL and FKS_TEST_TOKEN to run"))
struct EndToEndTests {

    private let server = TestServer.fromEnvironment()!

    /// Applies the test server config under the global config lock — see
    /// ConfigIsolation for why a bespoke save/restore isn't enough.
    private func withTestServer(_ body: () async throws -> Void) async rethrows {
        try await ConfigIsolation.withConfig(url: server.url, token: server.token, body)
    }

    @Test("the connection check passes against the real server")
    func connectionCheck() async {
        #expect(await SyncAPI.checkHealth(baseURL: server.url, token: server.token) == .ok)
    }

    @Test("the connection check rejects a wrong token against the real server")
    func realBadToken() async {
        // Proves the /stats step is doing real work, not just mirroring /health.
        #expect(await SyncAPI.checkHealth(baseURL: server.url, token: "definitely-wrong")
                == .unauthorized)
    }

    /// A synthetic packet. Ids are namespaced per run so repeated runs don't
    /// interfere, and the data is obviously fake — nothing here resembles a
    /// real transaction.
    private func syntheticPacket(id: String, amount: Double) -> SyncPacket {
        let accountId = "e2e-account-\(id)"
        var wallet = makePayload(accountId: accountId, amount: String(amount))
        wallet.accountDisplayName = "E2E Test Card"

        return SyncPacket(
            schemaVersion: 1,
            accounts: [SyncAccount(id: accountId, name: "E2E Test Card",
                                   institution: "Test Bank",
                                   balance: 100, currency: "USD")],
            transactions: [SyncTransaction(
                id: "e2e-txn-\(id)", accountId: accountId,
                date: "2026-08-01T12:00:00.000Z", amount: amount, currency: "USD",
                payee: "E2E TEST MERCHANT", status: "posted", notes: "booked",
                category: "5814",
                metadata: WalletMetadata(source: "financekitsync-e2e",
                                         sourceVersion: "test", wallet: wallet)
            )]
        )
    }

    @Test("a real packet reaches the real server and is stored")
    func realPacketRoundTrip() async throws {
        // Covers everything between the app and the database except the
        // FinanceKit read itself: encoding, auth, TLS, transport, the server's
        // upsert, and receipt decoding.
        let api = SyncAPI(baseURL: server.url, token: server.token)
        let id = UUID().uuidString

        let first = try await api.send(packet: syntheticPacket(id: id, amount: -42.10))
        #expect(first.transactionsReceived == 1)
        #expect(first.transactionsInserted == 1)
        #expect(first.transactionsUpdated == 0)

        // Replay must be idempotent — this is what lets the client treat a lost
        // ledger write as harmless.
        let replay = try await api.send(packet: syntheticPacket(id: id, amount: -42.10))
        #expect(replay.transactionsInserted == 0)
        #expect(replay.transactionsUpdated == 1)

        // A correction updates in place rather than duplicating.
        let corrected = try await api.send(packet: syntheticPacket(id: id, amount: -99.99))
        #expect(corrected.transactionsInserted == 0)
        #expect(corrected.transactionsUpdated == 1)
    }

    @Test("an accounts-only packet is accepted")
    func accountsOnlyPacket() async throws {
        // The path a no-op sync takes, so the server still gets fresh balances.
        let api = SyncAPI(baseURL: server.url, token: server.token)
        let receipt = try await api.send(
            packet: SyncPacket(schemaVersion: 1, accounts: [], transactions: [])
        )
        #expect(receipt.transactionsReceived == 0)
    }

    @Test("the real server rejects a bad token")
    func realServerRejectsBadToken() async {
        let api = SyncAPI(baseURL: server.url, token: "definitely-wrong")
        do {
            _ = try await api.send(
                packet: SyncPacket(schemaVersion: 1, accounts: [], transactions: [])
            )
            Issue.record("expected the server to reject the token")
        } catch {
            #expect(error as? SyncAPI.APIError == .unauthorized)
        }
    }

    @Test("the engine skips in the simulator rather than reaching the server")
    func engineSkipsInSimulator() async throws {
        // Documents the boundary: with the config applied and the server
        // reachable, the engine still stops at the simulator guard. The
        // FinanceKit-dependent half of the pipeline is only exercisable on a
        // real device — see docs/workstream-app.md.
        try await withTestServer {
            #if targetEnvironment(simulator)
            guard case .skipped = await SyncEngine.run(log: { _ in }) else {
                Issue.record("expected .skipped in the simulator")
                return
            }
            #endif
        }
    }
}
