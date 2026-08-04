//
//  SyncLedgerTests.swift
//  FinanceKitSyncTests
//
//  The ledger is what stops the app re-sending the whole history every run.
//  These use an in-memory store rather than the real Application Support file.
//
import Testing
import Foundation
import SwiftData
@testable import FinanceKitSync

private func makeLedger() throws -> SyncLedger {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Schema([SyncRecord.self]), configurations: [config])
    return SyncLedger(context: ModelContext(container))
}

@Suite("Sync ledger")
struct SyncLedgerTests {

    @Test("starts empty")
    func startsEmpty() throws {
        let ledger = try makeLedger()
        #expect(try ledger.recordsById().isEmpty)
        #expect(ledger.count() == 0)
    }

    @Test("acknowledging inserts records")
    func inserts() throws {
        let ledger = try makeLedger()
        var existing = try ledger.recordsById()
        try ledger.acknowledge([("a", "h1"), ("b", "h2")], existing: &existing, at: Date())

        #expect(ledger.count() == 2)
        #expect(try ledger.recordsById()["a"]?.contentHash == "h1")
        // The inout map must reflect the inserts, or the next batch in the same
        // run would insert duplicates and trip the unique constraint.
        #expect(existing.count == 2)
    }

    @Test("acknowledging the same id twice updates rather than duplicating")
    func upserts() throws {
        let ledger = try makeLedger()
        var existing = try ledger.recordsById()
        try ledger.acknowledge([("a", "h1")], existing: &existing, at: Date())
        try ledger.acknowledge([("a", "h2")], existing: &existing, at: Date())

        #expect(ledger.count() == 1)
        #expect(try ledger.recordsById()["a"]?.contentHash == "h2")
    }

    @Test("a repeated id within one batch doesn't trip the unique constraint")
    func duplicateWithinBatch() throws {
        // This is the case the inout `existing` map exists for: without it the
        // second entry would insert a second row and the save would throw.
        let ledger = try makeLedger()
        var existing = try ledger.recordsById()
        try ledger.acknowledge([("a", "h1"), ("a", "h2")], existing: &existing, at: Date())

        #expect(ledger.count() == 1)
        #expect(try ledger.recordsById()["a"]?.contentHash == "h2")
    }

    @Test("the diff selects unseen and changed rows only")
    func diffSelects() throws {
        let ledger = try makeLedger()
        var existing = try ledger.recordsById()
        try ledger.acknowledge([("seen-same", "h1"), ("seen-changed", "h1")],
                               existing: &existing, at: Date())

        // Mirrors the filter in SyncEngine.run.
        let candidates = [("seen-same", "h1"), ("seen-changed", "h2"), ("brand-new", "h3")]
        let records = try ledger.recordsById()
        let toSend = candidates.filter { records[$0.0]?.contentHash != $0.1 }

        #expect(toSend.map(\.0).sorted() == ["brand-new", "seen-changed"])
    }

    @Test("reset clears everything so the next run replays the full history")
    func reset() throws {
        let ledger = try makeLedger()
        var existing = try ledger.recordsById()
        try ledger.acknowledge([("a", "h1"), ("b", "h2")], existing: &existing, at: Date())
        #expect(ledger.count() == 2)

        try ledger.reset()
        #expect(ledger.count() == 0)
        #expect(try ledger.recordsById().isEmpty)
    }

    @Test("persists only bookkeeping, never financial values")
    func storesNoFinancialData() throws {
        // A privacy claim the landing page and the App Store listing both make,
        // so it gets asserted rather than assumed. Asks SwiftData's schema what
        // is actually persisted, rather than reflecting over the instance —
        // @Model synthesizes extra stored properties that aren't columns.
        let persisted = Set(
            Schema([SyncRecord.self]).entities
                .flatMap(\.properties)
                .map(\.name)
        )
        #expect(persisted == ["id", "contentHash", "mirroredAt"],
                "unexpected persisted properties: \(persisted.sorted())")
    }
}
