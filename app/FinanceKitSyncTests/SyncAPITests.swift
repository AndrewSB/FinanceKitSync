//
//  SyncAPITests.swift
//  FinanceKitSyncTests
//
//  Wire format and the two-step connection check, against a stubbed transport.
//
import Testing
import Foundation
@testable import FinanceKitSync

// MARK: - Stub transport

/// Intercepts URLSession traffic so these tests never touch the network.
///
/// Swift Testing runs suites in parallel, so this state is shared across
/// concurrently-executing tests. Rather than resetting it per test — which had
/// tests clobbering each other's stubs — every test claims its own hostname and
/// all lookups are keyed on `host + path`. Nothing is ever removed, so there is
/// no window in which one test's teardown breaks another's setup.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var responses: [String: (Int, Data)] = [:]
        var unreachable: Set<String> = []
        var recorded: [URLRequest] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    private static func key(_ url: URL?) -> String {
        guard let url else { return "" }
        return (url.host ?? "") + url.path
    }

    /// Registers a canned response. `host` scopes it to one test.
    static func stub(host: String, path: String, status: Int, body: Data = Data()) {
        lock.withLock { state.responses[host + path] = (status, body) }
    }

    /// Makes requests to this host+path fail at the transport layer.
    static func stubUnreachable(host: String, path: String) {
        lock.withLock { _ = state.unreachable.insert(host + path) }
    }

    /// Requests seen for one host, for asserting on headers and bodies.
    static func requests(host: String) -> [URLRequest] {
        lock.withLock { state.recorded.filter { $0.url?.host == host } }
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let k = Self.key(request.url)
        let outcome: (Int, Data)? = Self.lock.withLock {
            Self.state.recorded.append(request)
            if Self.state.unreachable.contains(k) { return nil }
            return Self.state.responses[k] ?? (404, Data())
        }

        guard let (status, body) = outcome else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private let healthOK = Data(#"{"status":"ok","schema_version":1}"#.utf8)

private func url(_ host: String) -> URL { URL(string: "https://\(host)")! }

// MARK: - Wire format

@Suite("Packet encoding")
struct PacketEncodingTests {

    @Test("uses the snake_case keys the server expects")
    func snakeCaseKeys() throws {
        let packet = SyncPacket(
            schemaVersion: 1,
            accounts: [SyncAccount(id: "a", name: "Apple Card",
                                   institution: "GS", balance: 10.5, currency: "USD")],
            transactions: [SyncTransaction(
                id: "t", accountId: "a", date: "2026-08-01T12:00:00.000Z",
                amount: -42.10, currency: "USD", payee: "COFFEE",
                status: "posted", notes: "booked", category: "5814",
                metadata: WalletMetadata(source: "financekitsync", sourceVersion: "1.0",
                                         wallet: makePayload())
            )]
        )

        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(packet)
        ) as! [String: Any]

        // A rename here silently breaks every deployed server.
        #expect(json["schema_version"] as? Int == 1)
        // Stable across packets: the server keys device aliases on it.
        #expect(json["device_install_id"] as? String == ServerConfig.deviceInstallID)
        #expect(UUID(uuidString: ServerConfig.deviceInstallID) != nil)
        let txn = (json["transactions"] as! [[String: Any]])[0]
        #expect(txn["account_id"] as? String == "a")
        #expect(txn["id"] as? String == "t")
        #expect(txn["amount"] as? Double == -42.10)

        let wallet = (txn["metadata"] as! [String: Any])["wallet"] as! [String: Any]
        #expect(wallet["transaction_id"] as? String == "txn-1")
        #expect(wallet["merchant_category_code"] as? String == "5814")
    }

    @Test("sends account balances as exact decimals")
    func exactBalance() throws {
        // Through a Double this went out as 13139.189999999999.
        let account = SyncAccount(id: "a", name: "Apple Card", institution: "GS",
                                  balance: Decimal(string: "13139.19")!, currency: "USD")
        let json = String(decoding: try JSONEncoder().encode(account), as: UTF8.self)
        #expect(json.contains(#""balance":13139.19,"#) || json.hasSuffix(#""balance":13139.19}"#))
    }

    @Test("leaves out a balance that isn't known")
    func unknownBalance() throws {
        let account = SyncAccount(id: "a", name: "Apple Card", institution: "GS",
                                  balance: nil, currency: "USD")
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(account)
        ) as! [String: Any]
        #expect(json["balance"] == nil)
        #expect(json["currency"] as? String == "USD")
    }

    @Test("decodes the server's receipt")
    func decodesReceipt() throws {
        let receipt = try JSONDecoder().decode(SyncReceipt.self, from: Data(#"""
        {"accounts_received":2,"transactions_received":500,
         "transactions_inserted":480,"transactions_updated":20}
        """#.utf8))
        #expect(receipt.transactionsInserted == 480)
        #expect(receipt.transactionsUpdated == 20)
    }
}

// MARK: - Connection check

@Suite("Connection check")
struct ConnectionCheckTests {

    private func check(host: String, token: String?) async -> SyncAPI.HealthResult {
        await SyncAPI.checkHealth(
            baseURL: url(host), token: token, session: StubURLProtocol.session()
        )
    }

    @Test("reports ok when health and token both pass")
    func happyPath() async {
        let host = "happy-path.test"
        StubURLProtocol.stub(host: host, path: "/health", status: 200, body: healthOK)
        StubURLProtocol.stub(host: host, path: "/stats", status: 200, body: Data("{}".utf8))
        #expect(await check(host: host, token: "good") == .ok)
    }

    @Test("reports unauthorized when the token is refused")
    func badToken() async {
        // The bug this guards: /health is unauthenticated, so checking only
        // /health reported "Connected" for any wrong token and deferred the
        // real failure to the first sync.
        let host = "bad-token.test"
        StubURLProtocol.stub(host: host, path: "/health", status: 200, body: healthOK)
        StubURLProtocol.stub(host: host, path: "/stats", status: 401)
        #expect(await check(host: host, token: "wrong") == .unauthorized)
    }

    @Test("reports unauthorized when no token is supplied")
    func noToken() async {
        let host = "no-token.test"
        StubURLProtocol.stub(host: host, path: "/health", status: 200, body: healthOK)
        #expect(await check(host: host, token: "") == .unauthorized)
    }

    @Test("does not send the token to the unauthenticated health endpoint")
    func healthIsAnonymous() async {
        let host = "anon-health.test"
        StubURLProtocol.stub(host: host, path: "/health", status: 200, body: healthOK)
        StubURLProtocol.stub(host: host, path: "/stats", status: 200, body: Data("{}".utf8))
        _ = await check(host: host, token: "secret")

        let health = StubURLProtocol.requests(host: host).first { $0.url?.path == "/health" }
        #expect(health != nil)
        #expect(health?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("rejects a server that answers but isn't ours")
    func wrongServer() async {
        let host = "not-ours.test"
        StubURLProtocol.stub(host: host, path: "/health", status: 200,
                             body: Data(#"{"hello":"world"}"#.utf8))
        guard case .unexpected = await check(host: host, token: "t") else {
            Issue.record("expected .unexpected")
            return
        }
    }

    @Test("rejects a server speaking a different schema version")
    func schemaMismatch() async {
        let host = "schema-v2.test"
        StubURLProtocol.stub(host: host, path: "/health", status: 200,
                             body: Data(#"{"status":"ok","schema_version":2}"#.utf8))
        guard case .unexpected = await check(host: host, token: "t") else {
            Issue.record("expected .unexpected")
            return
        }
    }

    @Test("reports unreachable when the host can't be contacted")
    func unreachable() async {
        let host = "unreachable.test"
        StubURLProtocol.stubUnreachable(host: host, path: "/health")
        guard case .unreachable = await check(host: host, token: "t") else {
            Issue.record("expected .unreachable")
            return
        }
    }
}

// MARK: - Error mapping

@Suite("Send error mapping")
struct SendErrorTests {

    private func send(host: String, status: Int, body: Data = Data()) async -> Error? {
        StubURLProtocol.stub(host: host, path: "/financekit-sync", status: status, body: body)
        let api = SyncAPI(baseURL: url(host), token: "t", session: StubURLProtocol.session())
        do {
            _ = try await api.send(
                packet: SyncPacket(schemaVersion: 1, accounts: [], transactions: [])
            )
            return nil
        } catch {
            return error
        }
    }

    @Test("401 maps to unauthorized, with actionable wording")
    func unauthorized() async {
        let error = await send(host: "send-401.test", status: 401)
        #expect(error as? SyncAPI.APIError == .unauthorized)
        // The message has to tell the user where to fix it.
        #expect(error?.localizedDescription.contains("Settings") == true)
    }

    @Test("413 maps to payloadTooLarge")
    func tooLarge() async {
        #expect(await send(host: "send-413.test", status: 413) as? SyncAPI.APIError == .payloadTooLarge)
    }

    @Test("422 carries the server's explanation")
    func schemaRejected() async {
        let error = await send(host: "send-422.test", status: 422,
                               body: Data("unsupported schema_version 9".utf8))
        guard case .schemaRejected(let detail)? = error as? SyncAPI.APIError else {
            Issue.record("expected .schemaRejected")
            return
        }
        #expect(detail.contains("schema_version"))
    }

    @Test("500 maps to serverError")
    func serverError() async {
        #expect(await send(host: "send-500.test", status: 500) as? SyncAPI.APIError
                == .serverError(statusCode: 500))
    }

    @Test("a 2xx with an unreadable body still counts as success")
    func lenientReceipt() async {
        // Failing here would re-send the batch forever against a server that
        // did accept it.
        #expect(await send(host: "send-200-bad-body.test", status: 200,
                           body: Data("not json".utf8)) == nil)
    }

    @Test("the bearer token is sent on every packet")
    func sendsToken() async {
        let host = "send-auth.test"
        _ = await send(host: host, status: 200, body: Data("{}".utf8))
        let request = StubURLProtocol.requests(host: host).first
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }
}
