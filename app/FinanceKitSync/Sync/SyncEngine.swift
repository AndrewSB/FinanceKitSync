//
//  SyncEngine.swift
//  FinanceKitSync
//
//  The whole pipeline: read FinanceKit (all accounts, the entire transaction
//  history), diff against the local ledger, POST what the server hasn't
//  acknowledged. Every failure is contained here — callers get an Outcome,
//  never a throw.
//
//  Ported from LunchSync's MirrorSyncEngine. The cross-process flock RunLock
//  and the background-extension detection are gone (single target now); an
//  actor serializes runs instead. Hashing, pagination, and batching are
//  unchanged — see docs/SPEC.md §3.1 before touching any of them.
//
import Foundation
import FinanceKit
import CryptoKit

/// Serializes engine runs within the process, so a "Sync now" tap can't race a
/// background task into the same ledger.
actor SyncEngineGate {
    static let shared = SyncEngineGate()
    private var running = false

    /// Returns false when a run is already in flight.
    func tryEnter() -> Bool {
        if running { return false }
        running = true
        return true
    }

    func leave() { running = false }
}

struct SyncEngine {

    enum Outcome {
        case notConfigured
        /// Nothing was attempted (e.g. a run is already in flight).
        case skipped(String)
        case success(sent: Int)
        case failure(sent: Int, error: Error)
    }

    /// Transactions per POST.
    private static let batchSize = 500
    /// Transactions per FinanceKit query page when walking the full history.
    private static let pageSize = 1000

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // nonisolated(unsafe): configured once here and only ever read from
    // afterwards. Formatting on a fully-configured NSFormatter is thread-safe;
    // the alternative — building one per transaction — allocates thousands of
    // formatters during a full-history backfill.
    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Runs a full pass when a server is configured. Never throws; `log`
    /// receives progress and diagnostic lines.
    static func run(log: @Sendable @escaping (String) -> Void = { print("SyncEngine: \($0)") }) async -> Outcome {
        guard let baseURL = ServerConfig.baseURL, let token = ServerConfig.token, !token.isEmpty else {
            return .notConfigured
        }

        guard await SyncEngineGate.shared.tryEnter() else {
            log("a sync is already running, skipping this run")
            return .skipped("already running")
        }
        defer { Task { await SyncEngineGate.shared.leave() } }

        // Graceful failure: no ledger, no run. A run without dedupe bookkeeping
        // would re-send the whole history every time.
        guard let ledger = SyncLedger.open() else {
            log("ledger store unavailable, skipping this run")
            return .failure(sent: 0, error: NSError(
                domain: "SyncEngine", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "The local ledger could not be opened"]
            ))
        }

        do {
            // FinanceKit traps rather than throws when its store can't be
            // opened, so bail out before querying.
            if !isSimulator {
                guard FinanceStore.isDataAvailable(.financialData) else {
                    throw NSError(domain: "SyncEngine", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "Financial data isn't available on this device."
                    ])
                }
                let status = try await FinanceStore.shared.requestAuthorization()
                guard status == .authorized else {
                    throw NSError(domain: "SyncEngine", code: -4, userInfo: [
                        NSLocalizedDescriptionKey:
                            "Access to financial data isn't authorized. Grant it in Settings › Privacy & Security › Financial Data."
                    ])
                }
            }

            // All accounts with current balances. Accounts ride along on every
            // packet so the server can always reconcile names and balances.
            let (accounts, accountInfoById) = try await fetchAccounts(log: log)

            // The entire FinanceKit history, oldest first.
            let history = try await fetchFullHistory(log: log)
            log("\(accounts.count) accounts, \(history.count) transactions in FinanceKit history")

            var entries: [(id: String, hash: String, packet: SyncTransaction)] = []
            entries.reserveCapacity(history.count)
            for txn in history {
                let (packet, hash) = packetEntry(for: txn, info: accountInfoById[txn.accountID])
                entries.append((id: packet.id, hash: hash, packet: packet))
            }

            var existing = try ledger.recordsById()
            // Send anything the ledger has never seen, or whose content changed
            // since the server last acknowledged it.
            let toSend = entries.filter { existing[$0.id]?.contentHash != $0.hash }
            log("\(toSend.count) of \(entries.count) transactions need sending (\(existing.count) already acknowledged)")

            let api = SyncAPI(baseURL: baseURL, token: token)

            // Nothing new: still send one accounts-only packet so the server
            // gets fresh balances on every sync.
            if toSend.isEmpty {
                try await api.send(packet: SyncPacket(
                    schemaVersion: 1, accounts: accounts, transactions: []
                ))
                log("up to date, sent accounts-only packet")
                return .success(sent: 0)
            }

            var sent = 0
            var start = 0
            while start < toSend.count {
                let batch = Array(toSend[start ..< min(start + batchSize, toSend.count)])
                start += batch.count
                do {
                    try await api.send(packet: SyncPacket(
                        schemaVersion: 1,
                        accounts: accounts,
                        transactions: batch.map(\.packet)
                    ))
                } catch {
                    // Stop on first failure; everything unacknowledged is
                    // retried on the next run.
                    log("batch failed after \(sent) sent: \(error.localizedDescription)")
                    return .failure(sent: sent, error: error)
                }
                do {
                    try ledger.acknowledge(batch.map { ($0.id, $0.hash) }, existing: &existing, at: Date())
                } catch {
                    // The server did ack this batch; a lost upsert only means a
                    // harmless resend next run (the server upserts too).
                    log("ledger save failed (batch will be resent next run): \(error.localizedDescription)")
                }
                sent += batch.count
                log("sent \(sent)/\(toSend.count)")
            }
            return .success(sent: sent)
        } catch {
            log("run failed: \(error.localizedDescription)")
            return .failure(sent: 0, error: error)
        }
    }

    // MARK: - FinanceKit fetches

    struct AccountInfo {
        let displayName: String
        let institutionName: String
    }

    /// All FinanceKit accounts plus their latest balances. An account whose
    /// balance lookup fails is still reported (balance 0) rather than dropped —
    /// its transactions matter regardless.
    private static func fetchAccounts(
        log: @Sendable (String) -> Void
    ) async throws -> ([SyncAccount], [UUID: AccountInfo]) {
        let query = AccountQuery(
            sortDescriptors: [SortDescriptor(\FinanceKit.Account.displayName)],
            predicate: nil
        )
        let accounts = try await FinanceStore.shared.accounts(query: query)

        var syncAccounts: [SyncAccount] = []
        var infoById: [UUID: AccountInfo] = [:]
        for acct in accounts {
            var balance = 0.0
            var currency = "USD"
            do {
                let latest = try await latestBalance(accountId: acct.id)
                var amount: CurrencyAmount?
                switch latest.currentBalance {
                case .availableAndBooked(let available, let booked):
                    amount = (available.creditDebitIndicator == .credit) ? booked.amount : available.amount
                case .available(let available):
                    amount = available.amount
                case .booked(let booked):
                    amount = booked.amount
                @unknown default:
                    log("unknown balance type for \(acct.displayName)")
                }
                if let amount {
                    balance = NSDecimalNumber(decimal: amount.amount).doubleValue
                    currency = amount.currencyCode
                }
            } catch {
                log("no balance for \(acct.displayName): \(error.localizedDescription)")
            }
            syncAccounts.append(SyncAccount(
                id: acct.id.uuidString,
                name: acct.displayName,
                institution: acct.institutionName,
                balance: balance,
                currency: currency
            ))
            infoById[acct.id] = AccountInfo(
                displayName: acct.displayName,
                institutionName: acct.institutionName
            )
        }
        return (syncAccounts, infoById)
    }

    private static func latestBalance(accountId: UUID) async throws -> AccountBalance {
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let query = AccountBalanceQuery(
            sortDescriptors: [],
            predicate: AccountBalanceQuery.predicate(bookedSince: startDate),
            limit: 100,
            offset: 0
        )
        let balances = try await FinanceStore.shared.accountBalances(query: query)
            .filter { $0.accountID == accountId }
        guard let latest = balances.max(by: { balanceAsOfDate($0) < balanceAsOfDate($1) }) else {
            throw NSError(domain: "SyncEngine", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "No balance found"
            ])
        }
        return latest
    }

    private static func balanceAsOfDate(_ balance: AccountBalance) -> Date {
        switch balance.currentBalance {
        case .availableAndBooked(_, let booked):    return booked.asOfDate
        case .available(let available):             return available.asOfDate
        case .booked(let booked):                   return booked.asOfDate
        @unknown default:                           return Date.distantPast
        }
    }

    /// The whole transaction history: no date predicate, date ascending,
    /// paginated through TransactionQuery's limit/offset.
    private static func fetchFullHistory(log: @Sendable (String) -> Void) async throws -> [FinanceKit.Transaction] {
        // Secondary sort on id keeps the ordering stable when many rows share a
        // timestamp, so page boundaries can't shuffle between executions.
        let sortDescriptors = [
            SortDescriptor(\FinanceKit.Transaction.transactionDate, order: .forward),
            SortDescriptor(\FinanceKit.Transaction.id, order: .forward)
        ]
        var seen = Set<UUID>()
        var fetched: [FinanceKit.Transaction] = []
        var offset = 0
        var duplicates = 0
        while true {
            let query = TransactionQuery(
                sortDescriptors: sortDescriptors,
                predicate: nil,
                limit: pageSize,
                offset: offset
            )
            let page = try await FinanceStore.shared.transactions(query: query)
            var newRows = 0
            for txn in page where seen.insert(txn.id).inserted {
                fetched.append(txn)
                newRows += 1
            }
            duplicates += page.count - newRows
            // Progress guarantee: stop as soon as a page contributes zero NEW
            // ids. That covers the normal empty last page, a short page that
            // wasn't actually the end (the next request re-asks), and the
            // pathological cases — offset ignored/clamped, or a repeating page
            // — which would otherwise loop forever and grow `fetched` without
            // bound.
            if newRows == 0 { break }
            offset += page.count
            log("fetched \(fetched.count) transactions so far…")
        }
        if duplicates > 0 {
            log("dropped \(duplicates) duplicate rows across pages")
        }
        return fetched
    }

    // MARK: - Mapping & hashing

    /// Maps one FinanceKit transaction to a packet entry, plus the stable
    /// content hash used for change detection.
    private static func packetEntry(
        for txn: FinanceKit.Transaction,
        info: AccountInfo?
    ) -> (SyncTransaction, String) {
        var amount = NSDecimalNumber(decimal: txn.transactionAmount.amount).doubleValue
        if txn.creditDebitIndicator == .credit {
            amount = amount * -1
        }
        let status = txn.status == .booked ? "posted" : "pending"

        let metadata = WalletMetadata(
            from: txn,
            accountDisplayName: info?.displayName,
            institutionName: info?.institutionName
        )
        let wallet = metadata.wallet

        let packet = SyncTransaction(
            id: txn.id.uuidString,
            accountId: txn.accountID.uuidString,
            date: isoFormatter.string(from: txn.transactionDate),
            amount: amount,
            currency: txn.transactionAmount.currencyCode,
            payee: txn.transactionDescription,
            status: status,
            notes: txn.status == .booked ? "booked" : "pending",
            category: wallet.merchantCategoryCode ?? "",
            metadata: metadata
        )

        // SHA-256 over a canonical string of the change-relevant fields —
        // deliberately not Hasher/hashValue, whose seed is randomized per
        // process (which would re-send the entire history on every launch).
        // Any correction that alters what the packet carries changes the hash
        // and re-queues the row. nil encodes distinctly from empty string.
        let nilMarker = "\u{1}nil"
        let canonical = [
            wallet.accountId,
            wallet.amount.value,
            wallet.amount.currency,
            wallet.creditDebitIndicator,
            wallet.transactionDate,
            wallet.postedDate ?? nilMarker,
            status,
            wallet.transactionType,
            wallet.transactionDescription,
            wallet.originalTransactionDescription ?? nilMarker,
            wallet.merchantName ?? nilMarker,
            wallet.merchantCategoryCode ?? nilMarker,
            wallet.foreignAmount?.value ?? nilMarker,
            wallet.foreignAmount?.currency ?? nilMarker,
            wallet.foreignExchangeRate ?? nilMarker
        ].joined(separator: "|")
        let hash = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return (packet, hash)
    }
}
