//
//  SyncAPI.swift
//  FinanceKitSync
//
//  The wire format and the client that speaks it. Ported from LunchSync's
//  MirrorAPI; the packet schema is unchanged (schema_version 1) but every
//  request now carries a bearer token.
//
import Foundation

// MARK: - Packet schema (schema_version 1)

struct SyncPacket: Encodable {
    let schemaVersion: Int
    let accounts: [SyncAccount]
    let transactions: [SyncTransaction]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case accounts
        case transactions
    }
}

struct SyncAccount: Encodable {
    let id: String
    let name: String
    let institution: String
    let balance: Double
    let currency: String
}

struct SyncTransaction: Encodable {
    let id: String
    let accountId: String
    let date: String
    let amount: Double
    let currency: String
    let payee: String
    let status: String
    let notes: String
    let category: String
    /// The full FinanceKit capture, as a nested JSON object.
    let metadata: WalletMetadata

    private enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case date
        case amount
        case currency
        case payee
        case status
        case notes
        case category
        case metadata
    }
}

/// What the server reports back about a packet.
struct SyncReceipt: Decodable {
    let accountsReceived: Int
    let transactionsReceived: Int
    let transactionsInserted: Int
    let transactionsUpdated: Int

    private enum CodingKeys: String, CodingKey {
        case accountsReceived = "accounts_received"
        case transactionsReceived = "transactions_received"
        case transactionsInserted = "transactions_inserted"
        case transactionsUpdated = "transactions_updated"
    }
}

// MARK: - Client

struct SyncAPI {
    let baseURL: URL
    let token: String
    /// Injectable so tests can stub the transport. Production always uses
    /// `.shared`, which gets the system's connection reuse and proxy handling.
    let session: URLSession

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    enum APIError: LocalizedError, Equatable {
        case badResponse
        case unauthorized
        case payloadTooLarge
        case schemaRejected(String)
        case serverError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .badResponse:
                return "The server returned an unexpected response."
            case .unauthorized:
                return "The server rejected the token (401). Check the token in Settings."
            case .payloadTooLarge:
                return "The server rejected the batch as too large (413)."
            case .schemaRejected(let detail):
                return "The server rejected the packet format: \(detail)"
            case .serverError(let statusCode):
                return "The server returned HTTP \(statusCode)."
            }
        }
    }

    /// Result of an onboarding / settings connection test.
    enum HealthResult: Equatable {
        case ok
        /// Reachable, but the token was refused.
        case unauthorized
        /// Reachable, but not something that looks like our server.
        case unexpected(String)
        case unreachable(String)
    }

    private static func request(_ url: URL, method: String, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Two-step connection check.
    ///
    /// `GET /health` is unauthenticated by design, so onboarding can prove the
    /// *address* is right before a token is entered — but that means a 200 from
    /// it says nothing about whether the token is valid. Checking only /health
    /// would report "Connected" for any typo'd token and defer the real failure
    /// to the first sync, which is exactly when it's least debuggable.
    ///
    /// So: /health proves we're talking to a FinanceKitSync server, then an
    /// authenticated endpoint proves the token works.
    ///
    /// Static because it must work before a `SyncAPI` can be constructed.
    static func checkHealth(
        baseURL: URL, token: String?, session: URLSession = .shared
    ) async -> HealthResult {
        // Step 1 — is this our server, and is it reachable?
        do {
            let url = baseURL.appendingPathComponent("health")
            let (data, response) = try await session.data(
                for: request(url, method: "GET", token: nil)
            )
            guard let http = response as? HTTPURLResponse else {
                return .unexpected("no HTTP response")
            }
            guard http.statusCode == 200 else {
                return .unexpected("HTTP \(http.statusCode) from /health")
            }
            // Confirm it's actually our server and not some other service that
            // happens to answer /health with a 200.
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "ok" else {
                return .unexpected("something is listening, but it isn't a FinanceKitSync server")
            }
            if let version = json["schema_version"] as? Int, version != 1 {
                return .unexpected("server speaks schema v\(version), this app speaks v1")
            }
        } catch {
            return .unreachable(error.localizedDescription)
        }

        // Step 2 — does the token actually work?
        guard let token, !token.isEmpty else { return .unauthorized }
        do {
            let url = baseURL.appendingPathComponent("stats")
            let (_, response) = try await session.data(
                for: request(url, method: "GET", token: token)
            )
            guard let http = response as? HTTPURLResponse else {
                return .unexpected("no HTTP response")
            }
            switch http.statusCode {
            case 200...299:    return .ok
            case 401, 403:     return .unauthorized
            default:           return .unexpected("HTTP \(http.statusCode) from /stats")
            }
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    /// POSTs one packet. Throws on transport failure or any non-2xx.
    @discardableResult
    func send(packet: SyncPacket) async throws -> SyncReceipt {
        let url = baseURL.appendingPathComponent("financekit-sync")
        var request = Self.request(url, method: "POST", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(packet)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badResponse
        }
        switch http.statusCode {
        case 200...299:
            // A server that 2xx'd but sent an unreadable body still counted the
            // rows — treat the receipt as best-effort rather than failing the
            // batch and re-sending it forever.
            return (try? JSONDecoder().decode(SyncReceipt.self, from: data))
                ?? SyncReceipt(
                    accountsReceived: packet.accounts.count,
                    transactionsReceived: packet.transactions.count,
                    transactionsInserted: 0,
                    transactionsUpdated: 0
                )
        case 401, 403:
            throw APIError.unauthorized
        case 413:
            throw APIError.payloadTooLarge
        case 422:
            let detail = String(data: data, encoding: .utf8) ?? "unknown"
            throw APIError.schemaRejected(String(detail.prefix(200)))
        default:
            throw APIError.serverError(statusCode: http.statusCode)
        }
    }
}
