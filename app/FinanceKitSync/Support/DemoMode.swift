//
//  DemoMode.swift
//  FinanceKitSync
//
//  A self-contained walkthrough of the whole app that needs neither a server
//  nor an Apple Card.
//
//  App Review asked for a way to exercise every feature without setting up a
//  server. In demo mode the app is wired to two stand-ins:
//
//    • `DemoDataset` plays the part of FinanceKit — a fixed, invented set of
//      accounts and transactions. Nothing is read from the real store.
//    • `DemoServer` plays the part of the receiver — an in-process URLProtocol
//      that answers /health, /stats and /financekit-sync exactly as the
//      Python server does, and keeps its "database" in memory.
//
//  Everything else — the engine, the ledger, the HTTP client, every view — is
//  the real code path. The sync really diffs against a ledger, really encodes a
//  packet, really POSTs it, and really acknowledges the receipt; only the two
//  ends are fake. That is deliberate: a reviewer sees the app as it behaves,
//  and a bug in the pipeline shows up in the demo too.
//
//  The demo keeps its own ledger file and is fenced off from real config, so
//  entering and leaving it never touches a user's actual server settings or
//  acknowledgement history.
//
import Foundation
import Observation

// MARK: - The switch

@MainActor
@Observable
final class DemoMode {
    static let shared = DemoMode()

    /// `.invalid` is reserved by RFC 2606 and can never resolve, so even if
    /// something bypassed `DemoServer` this address could not reach anyone.
    nonisolated static let serverURL = URL(string: "https://demo.financekitsync.invalid")!
    nonisolated static let token = "demo"

    private nonisolated static let activeKey = "demo_mode_active"
    private static let savedURLKey = "demo_mode_saved_url"

    /// Observable, for the UI. Same fact as `isEnabled`.
    private(set) var isActive: Bool

    /// The same flag, readable from any actor — the engine and `ServerConfig`
    /// run off the main actor and only need the current value.
    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: activeKey)
    }

    private init() {
        isActive = Self.isEnabled
    }

    /// Whether a given server address is the demo stand-in. Lets the
    /// connection test route to `DemoServer` only for that address, so someone
    /// typing a real server into Settings while in demo mode still gets a real
    /// connection test.
    nonisolated static func isDemoURL(_ url: URL) -> Bool {
        url.host?.lowercased() == serverURL.host
    }

    /// The transport the API client should use for `url`.
    nonisolated static func session(for url: URL) -> URLSession {
        isDemoURL(url) ? DemoServer.session : .shared
    }

    /// Switches the app to the demo stand-ins. The user's real server address
    /// is parked so it comes back when the demo ends; the token stays in the
    /// Keychain untouched because the demo never reads it.
    func enter() {
        guard !isActive else { return }
        let defaults = UserDefaults.standard
        defaults.set(ServerConfig.baseURLString, forKey: Self.savedURLKey)
        defaults.set(true, forKey: Self.activeKey)
        isActive = true

        ServerConfig.setBaseURL(Self.serverURL)
        DemoServer.reset()
        SyncCoordinator.shared.reloadAfterModeChange()
        Log.append("demo mode on — transactions and server are simulated")
    }

    /// Restores whatever was configured before the demo. If nothing was, the
    /// app returns to onboarding.
    func leave() {
        guard isActive else { return }
        let defaults = UserDefaults.standard
        let savedURL = defaults.string(forKey: Self.savedURLKey) ?? ""
        defaults.removeObject(forKey: Self.savedURLKey)
        defaults.removeObject(forKey: Self.activeKey)
        isActive = false

        ServerConfig.setBaseURL(ServerConfig.validate(savedURL))
        DemoServer.reset()
        SyncCoordinator.shared.reloadAfterModeChange()
        Log.append("demo mode off")
    }
}

// MARK: - Stand-in for FinanceKit

/// A fixed set of invented accounts and transactions. Every value here is
/// fabricated; the dates are pinned to the calendar rather than to "now" so the
/// content hashes are identical from one launch to the next, which is what
/// lets the ledger's change detection work in the demo exactly as it does
/// against FinanceKit.
enum DemoDataset {
    struct Entry: Sendable {
        let id: String
        let hash: String
        let packet: SyncTransaction
        let date: Date
    }

    private struct Account {
        let key: String
        let name: String
        let institution: String
        let balance: Double
    }

    private struct Row {
        let account: Int
        let day: Int            // days before the anchor date
        let hour: Int
        let amount: String      // positive; sign comes from `credit`
        let credit: Bool
        let description: String
        let merchant: String?
        let mcc: String?
        let type: String
        let pending: Bool
        let foreign: (String, String, String)?   // amount, currency, rate
    }

    private static let accounts: [Account] = [
        Account(key: "apple-card", name: "Apple Card", institution: "Goldman Sachs", balance: 1_284.37),
        Account(key: "apple-cash", name: "Apple Cash", institution: "Green Dot Bank", balance: 212.50),
        Account(key: "savings", name: "Savings", institution: "Goldman Sachs", balance: 15_320.11),
    ]

    /// The most recent transaction lands on this date. Fixed on purpose — see
    /// the type comment.
    private static let anchor: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 4
        components.hour = 9; components.minute = 15
        components.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private static let rows: [Row] = [
        Row(account: 0, day: 0, hour: 0, amount: "4.85", credit: false, description: "Blue Bottle Coffee", merchant: "Blue Bottle Coffee", mcc: "5814", type: "pointOfSale", pending: true, foreign: nil),
        Row(account: 0, day: 0, hour: -3, amount: "62.40", credit: false, description: "Whole Foods Market", merchant: "Whole Foods Market", mcc: "5411", type: "pointOfSale", pending: true, foreign: nil),
        Row(account: 1, day: 1, hour: 2, amount: "40.00", credit: true, description: "Apple Cash from Maya", merchant: nil, mcc: nil, type: "transfer", pending: false, foreign: nil),
        Row(account: 0, day: 1, hour: -1, amount: "18.99", credit: false, description: "Netflix", merchant: "Netflix", mcc: "4899", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 2, hour: 4, amount: "37.12", credit: false, description: "Shell Oil", merchant: "Shell", mcc: "5541", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 2, hour: -5, amount: "129.00", credit: false, description: "Patagonia", merchant: "Patagonia", mcc: "5651", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 2, day: 3, hour: 0, amount: "500.00", credit: true, description: "Transfer from checking", merchant: nil, mcc: nil, type: "deposit", pending: false, foreign: nil),
        Row(account: 0, day: 4, hour: 1, amount: "12.50", credit: false, description: "Bay Area Rapid Transit", merchant: "BART", mcc: "4111", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 5, hour: 3, amount: "84.20", credit: false, description: "Trader Joe's", merchant: "Trader Joe's", mcc: "5411", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 5, hour: -2, amount: "9.99", credit: false, description: "Apple.com/bill", merchant: "Apple", mcc: "5734", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 1, day: 6, hour: 0, amount: "25.00", credit: false, description: "Apple Cash to Jordan", merchant: nil, mcc: nil, type: "transfer", pending: false, foreign: nil),
        Row(account: 0, day: 7, hour: 5, amount: "46.30", credit: false, description: "Zuni Cafe", merchant: "Zuni Cafe", mcc: "5812", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 8, hour: -4, amount: "129.00", credit: true, description: "Patagonia refund", merchant: "Patagonia", mcc: "5651", type: "refund", pending: false, foreign: nil),
        Row(account: 0, day: 9, hour: 2, amount: "31.75", credit: false, description: "Pharmaca", merchant: "Pharmaca", mcc: "5912", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 11, hour: 0, amount: "58.60", credit: false, description: "Café de Flore", merchant: "Café de Flore", mcc: "5812", type: "pointOfSale", pending: false, foreign: ("54.10", "EUR", "1.0832")),
        Row(account: 0, day: 11, hour: -6, amount: "212.94", credit: false, description: "Hôtel Le Marais", merchant: "Hôtel Le Marais", mcc: "7011", type: "pointOfSale", pending: false, foreign: ("196.60", "EUR", "1.0831")),
        Row(account: 0, day: 12, hour: 1, amount: "14.20", credit: false, description: "RATP Paris Metro", merchant: "RATP", mcc: "4111", type: "pointOfSale", pending: false, foreign: ("13.10", "EUR", "1.0840")),
        Row(account: 2, day: 13, hour: 0, amount: "41.19", credit: true, description: "Interest payment", merchant: nil, mcc: nil, type: "interest", pending: false, foreign: nil),
        Row(account: 0, day: 14, hour: 3, amount: "1500.00", credit: true, description: "Payment - thank you", merchant: nil, mcc: nil, type: "billPayment", pending: false, foreign: nil),
        Row(account: 0, day: 15, hour: 2, amount: "72.15", credit: false, description: "Rainbow Grocery", merchant: "Rainbow Grocery", mcc: "5411", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 16, hour: -1, amount: "23.00", credit: false, description: "Alamo Drafthouse", merchant: "Alamo Drafthouse", mcc: "7832", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 17, hour: 4, amount: "5.40", credit: false, description: "Ritual Coffee Roasters", merchant: "Ritual Coffee", mcc: "5814", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 1, day: 18, hour: 0, amount: "60.00", credit: true, description: "Apple Cash from Sam", merchant: nil, mcc: nil, type: "transfer", pending: false, foreign: nil),
        Row(account: 0, day: 19, hour: 2, amount: "142.88", credit: false, description: "PG&E", merchant: "Pacific Gas & Electric", mcc: "4900", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 20, hour: -3, amount: "27.60", credit: false, description: "Green Apple Books", merchant: "Green Apple Books", mcc: "5942", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 22, hour: 1, amount: "89.00", credit: false, description: "Verizon Wireless", merchant: "Verizon", mcc: "4814", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 23, hour: 5, amount: "16.45", credit: false, description: "Mission Chinese Food", merchant: "Mission Chinese Food", mcc: "5812", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 24, hour: 0, amount: "54.30", credit: false, description: "Chevron", merchant: "Chevron", mcc: "5541", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 2, day: 25, hour: 0, amount: "500.00", credit: true, description: "Transfer from checking", merchant: nil, mcc: nil, type: "deposit", pending: false, foreign: nil),
        Row(account: 0, day: 26, hour: 3, amount: "11.25", credit: false, description: "Tartine Bakery", merchant: "Tartine", mcc: "5462", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 27, hour: -2, amount: "66.99", credit: false, description: "Amazon.com", merchant: "Amazon", mcc: "5942", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 28, hour: 2, amount: "38.00", credit: false, description: "SFMOMA", merchant: "SFMOMA", mcc: "7991", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 30, hour: 1, amount: "18.99", credit: false, description: "Netflix", merchant: "Netflix", mcc: "4899", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 31, hour: 4, amount: "97.42", credit: false, description: "Whole Foods Market", merchant: "Whole Foods Market", mcc: "5411", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 1, day: 32, hour: 0, amount: "15.00", credit: false, description: "Apple Cash to Maya", merchant: nil, mcc: nil, type: "transfer", pending: false, foreign: nil),
        Row(account: 0, day: 33, hour: -1, amount: "24.80", credit: false, description: "Lyft", merchant: "Lyft", mcc: "4121", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 34, hour: 2, amount: "8.75", credit: false, description: "Blue Bottle Coffee", merchant: "Blue Bottle Coffee", mcc: "5814", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 36, hour: 3, amount: "310.00", credit: false, description: "Alaska Airlines", merchant: "Alaska Airlines", mcc: "3058", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 37, hour: 0, amount: "9.99", credit: false, description: "Apple.com/bill", merchant: "Apple", mcc: "5734", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 2, day: 38, hour: 0, amount: "39.87", credit: true, description: "Interest payment", merchant: nil, mcc: nil, type: "interest", pending: false, foreign: nil),
        Row(account: 0, day: 40, hour: 1, amount: "45.10", credit: false, description: "Bi-Rite Market", merchant: "Bi-Rite Market", mcc: "5411", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 41, hour: 5, amount: "1250.00", credit: true, description: "Payment - thank you", merchant: nil, mcc: nil, type: "billPayment", pending: false, foreign: nil),
        Row(account: 0, day: 43, hour: -4, amount: "22.30", credit: false, description: "Philz Coffee", merchant: "Philz Coffee", mcc: "5814", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 44, hour: 2, amount: "150.00", credit: false, description: "REI", merchant: "REI", mcc: "5941", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 46, hour: 0, amount: "63.20", credit: false, description: "Sightglass Coffee", merchant: "Sightglass", mcc: "5814", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 1, day: 47, hour: 0, amount: "100.00", credit: true, description: "Added from debit card", merchant: nil, mcc: nil, type: "deposit", pending: false, foreign: nil),
        Row(account: 0, day: 49, hour: 3, amount: "29.99", credit: false, description: "Spotify", merchant: "Spotify", mcc: "5735", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 51, hour: -2, amount: "82.60", credit: false, description: "Costco Wholesale", merchant: "Costco", mcc: "5300", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 53, hour: 1, amount: "13.50", credit: false, description: "La Taqueria", merchant: "La Taqueria", mcc: "5812", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 55, hour: 4, amount: "4.85", credit: false, description: "Blue Bottle Coffee", merchant: "Blue Bottle Coffee", mcc: "5814", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 58, hour: 0, amount: "18.99", credit: false, description: "Netflix", merchant: "Netflix", mcc: "4899", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 60, hour: 2, amount: "215.40", credit: false, description: "Southwest Airlines", merchant: "Southwest Airlines", mcc: "3066", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 2, day: 62, hour: 0, amount: "500.00", credit: true, description: "Transfer from checking", merchant: nil, mcc: nil, type: "deposit", pending: false, foreign: nil),
        Row(account: 0, day: 64, hour: 3, amount: "41.00", credit: false, description: "Sports Basement", merchant: "Sports Basement", mcc: "5941", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 66, hour: -3, amount: "9.99", credit: false, description: "Apple.com/bill", merchant: "Apple", mcc: "5734", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 69, hour: 1, amount: "1100.00", credit: true, description: "Payment - thank you", merchant: nil, mcc: nil, type: "billPayment", pending: false, foreign: nil),
        Row(account: 0, day: 71, hour: 2, amount: "76.35", credit: false, description: "Whole Foods Market", merchant: "Whole Foods Market", mcc: "5411", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 74, hour: 5, amount: "34.00", credit: false, description: "Foreign Cinema", merchant: "Foreign Cinema", mcc: "5812", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 78, hour: 0, amount: "58.11", credit: false, description: "Shell Oil", merchant: "Shell", mcc: "5541", type: "pointOfSale", pending: false, foreign: nil),
        Row(account: 0, day: 83, hour: 3, amount: "12.00", credit: false, description: "Dolores Park Cafe", merchant: "Dolores Park Cafe", mcc: "5814", type: "pointOfSale", pending: false, foreign: nil),
    ]

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let syncAccounts: [SyncAccount] = accounts.map {
        SyncAccount(
            id: stableUUID("account:\($0.key)"),
            name: $0.name,
            institution: $0.institution,
            balance: $0.balance,
            currency: "USD"
        )
    }

    /// Ordered oldest first, matching what the engine gets from FinanceKit.
    static let entries: [Entry] = {
        rows.enumerated().map { index, row in entry(for: row, index: index) }
            .sorted { $0.date < $1.date }
    }()

    static var snapshot: SyncEngine.LocalSnapshot {
        SyncEngine.LocalSnapshot(
            accounts: syncAccounts,
            transactions: entries.map {
                SyncEngine.LocalTransactionRecord(transaction: $0.packet, transactionDate: $0.date)
            }
        )
    }

    private static func entry(for row: Row, index: Int) -> Entry {
        let account = accounts[row.account]
        let date = anchor.addingTimeInterval(TimeInterval(-row.day * 86_400 + row.hour * 3_600))
        let posted = row.pending ? nil : date.addingTimeInterval(86_400)
        let status = row.pending ? "pending" : "posted"
        let wallet = WalletMetadata.WalletPayload(
            transactionId: stableUUID("transaction:\(index)"),
            accountId: stableUUID("account:\(account.key)"),
            accountDisplayName: account.name,
            institutionName: account.institution,
            transactionDate: isoFormatter.string(from: date),
            postedDate: posted.map { isoFormatter.string(from: $0) },
            status: row.pending ? "pending" : "booked",
            isPending: row.pending,
            transactionType: row.type,
            creditDebitIndicator: row.credit ? "credit" : "debit",
            transactionDescription: row.description,
            originalTransactionDescription: row.merchant.map { $0.uppercased() },
            merchantName: row.merchant,
            merchantCategoryCode: row.mcc,
            merchantCategoryDescription: nil,
            amount: WalletMetadata.Money(value: row.amount, currency: "USD"),
            foreignAmount: row.foreign.map { WalletMetadata.Money(value: $0.0, currency: $0.1) },
            foreignExchangeRate: row.foreign?.2
        )
        let metadata = WalletMetadata(source: "financekitsync-demo", sourceVersion: nil, wallet: wallet)
        // Same sign convention as `SyncEngine.packetEntry`: credits negative.
        let magnitude = Double(row.amount) ?? 0
        let packet = SyncTransaction(
            id: wallet.transactionId,
            accountId: wallet.accountId,
            date: wallet.transactionDate,
            amount: row.credit ? -magnitude : magnitude,
            currency: "USD",
            payee: row.description,
            status: status,
            notes: row.pending ? "pending" : "booked",
            category: row.mcc ?? "",
            metadata: metadata
        )
        return Entry(
            id: packet.id,
            hash: SyncEngine.contentHash(wallet: wallet, status: status),
            packet: packet,
            date: date
        )
    }

    /// A UUID string derived from a name, so the ids are the same on every
    /// launch without having to hard-code sixty of them.
    private static func stableUUID(_ name: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        let second = hash &* 0x9E37_79B9_7F4A_7C15
        for i in 0..<8 {
            bytes[i] = UInt8((hash >> (8 * UInt64(i))) & 0xff)
            bytes[8 + i] = UInt8((second >> (8 * UInt64(i))) & 0xff)
        }
        // RFC 4122 variant/version bits, so the result looks like any other UUID.
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid.uuidString
    }
}

// MARK: - Stand-in for the server

/// An in-process receiver with the same routes and status codes as
/// `server/app/main.py`, so `SyncAPI` runs unmodified against it.
final class DemoServer: URLProtocol, @unchecked Sendable {
    private struct Store {
        var transactions: Set<String> = []
        var accounts = 0
        var packetsReceived = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var store = Store()

    /// A little latency per request, so "Syncing…" is actually visible.
    private static let latency: TimeInterval = 0.6

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoServer.self]
        return URLSession(configuration: config)
    }()

    /// Forgets everything received so far.
    static func reset() {
        lock.withLock { store = Store() }
    }

    /// How many distinct transactions the demo server has been sent.
    static var transactionCount: Int {
        lock.withLock { store.transactions.count }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url.map(DemoMode.isDemoURL) ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (status, body) = Self.handle(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.latency) { [self] in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private static func handle(_ request: URLRequest) -> (Int, Data) {
        let path = request.url?.path ?? ""
        if path == "/health" {
            return (200, json(["status": "ok", "schema_version": 1]))
        }

        let expected = "Bearer \(DemoMode.token)"
        guard request.value(forHTTPHeaderField: "Authorization") == expected else {
            return (401, json(["detail": "invalid token"]))
        }

        switch (request.httpMethod, path) {
        case ("GET", "/stats"):
            return lock.withLock {
                (200, json([
                    "accounts": store.accounts,
                    "transactions": store.transactions.count,
                    "packets_received": store.packetsReceived,
                ]))
            }

        case ("POST", "/financekit-sync"):
            guard let body = request.httpBody ?? request.httpBodyStream.map(readAll),
                  let packet = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  packet["schema_version"] as? Int == 1,
                  let accounts = packet["accounts"] as? [[String: Any]],
                  let transactions = packet["transactions"] as? [[String: Any]] else {
                return (422, json(["detail": "not a schema_version 1 packet"]))
            }
            return lock.withLock {
                var inserted = 0
                var updated = 0
                for txn in transactions {
                    guard let id = txn["id"] as? String else { continue }
                    if store.transactions.insert(id).inserted { inserted += 1 } else { updated += 1 }
                }
                store.accounts = max(store.accounts, accounts.count)
                store.packetsReceived += 1
                return (200, json([
                    "accounts_received": accounts.count,
                    "transactions_received": transactions.count,
                    "transactions_inserted": inserted,
                    "transactions_updated": updated,
                ]))
            }

        default:
            return (404, json(["detail": "not found"]))
        }
    }

    /// URLSession hands a POST body to a URLProtocol as a stream, not `httpBody`.
    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
