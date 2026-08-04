//
//  SyncLedger.swift
//  FinanceKitSync
//
//  Which FinanceKit transactions the server has acknowledged, and with what
//  content. Ported from LunchSync's MirrorLedger; the app-group container is
//  gone (single target now) so it lives in Application Support.
//
//  Note what this store deliberately does NOT contain: no amounts, no
//  merchants, no dates. Just an id, a hash, and a timestamp. If the device
//  database leaks, it reveals nothing about the user's finances.
//
import Foundation
import SwiftData

/// One acknowledged FinanceKit transaction. `id` is the FinanceKit transaction
/// UUID string, `contentHash` a stable digest of the fields the packet carries
/// (so a pending→posted flip or an amount correction re-queues the row), and
/// `mirroredAt` when the server last 2xx'd it.
@Model
final class SyncRecord {
    @Attribute(.unique) var id: String = ""
    var contentHash: String = ""
    var mirroredAt: Date = Date()

    init(id: String, contentHash: String, mirroredAt: Date) {
        self.id = id
        self.contentHash = contentHash
        self.mirroredAt = mirroredAt
    }
}

struct SyncLedger {
    static let storeFileName = "ledger.store"

    let context: ModelContext

    /// Opens (creating on first use) the ledger store. Returns nil rather than
    /// throwing — a run without dedupe bookkeeping would re-send the entire
    /// history every time, so the engine skips instead.
    static func open() -> SyncLedger? {
        guard let supportURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let storeURL = supportURL.appendingPathComponent(storeFileName)
        do {
            let schema = Schema([SyncRecord.self])
            // .none: local-only bookkeeping. CloudKit would also reject the
            // unique constraint on `id`.
            let configuration = ModelConfiguration(
                "SyncLedger", schema: schema, url: storeURL, cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return SyncLedger(context: ModelContext(container))
        } catch {
            return nil
        }
    }

    /// All acknowledged records, keyed by FinanceKit transaction id.
    func recordsById() throws -> [String: SyncRecord] {
        let records = try context.fetch(FetchDescriptor<SyncRecord>())
        return Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<SyncRecord>())) ?? 0
    }

    /// Upserts an acknowledged batch and saves.
    ///
    /// `existing` is inout: records inserted here are registered in it, so a
    /// repeated id later in the run updates the pending insert instead of
    /// adding a second row and tripping the unique constraint on save.
    ///
    /// Throws on save failure so the caller can log it. A lost upsert only
    /// costs a harmless resend, since the server upserts too. On failure the
    /// context is rolled back, so one bad save can't leave poisoned pending
    /// changes that make every later save fail.
    func acknowledge(
        _ entries: [(id: String, contentHash: String)],
        existing: inout [String: SyncRecord],
        at date: Date
    ) throws {
        var insertedIds: [String] = []
        for entry in entries {
            if let record = existing[entry.id] {
                record.contentHash = entry.contentHash
                record.mirroredAt = date
            } else {
                let record = SyncRecord(id: entry.id, contentHash: entry.contentHash, mirroredAt: date)
                context.insert(record)
                existing[entry.id] = record
                insertedIds.append(entry.id)
            }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            // The rolled-back inserts are no longer valid records; drop them
            // from the map so a retry re-inserts instead of mutating a ghost.
            for id in insertedIds {
                existing.removeValue(forKey: id)
            }
            throw error
        }
    }

    /// Forgets everything, so the next run replays the full history. Backs the
    /// "Re-send everything" button.
    func reset() throws {
        try context.delete(model: SyncRecord.self)
        try context.save()
    }
}
