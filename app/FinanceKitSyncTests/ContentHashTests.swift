//
//  ContentHashTests.swift
//  FinanceKitSyncTests
//
//  The content hash decides what gets re-sent. Wrong in one direction and
//  corrections are silently never delivered; wrong in the other and every
//  launch replays the entire history.
//
import Testing
import Foundation
@testable import FinanceKitSync

func makePayload(
    accountId: String = "acct-1",
    amount: String = "42.10",
    currency: String = "USD",
    creditDebit: String = "debit",
    transactionDate: String = "2026-08-01T12:00:00.000Z",
    postedDate: String? = "2026-08-02T12:00:00.000Z",
    transactionType: String = "pointOfSale",
    description: String = "BLUE BOTTLE COFFEE",
    originalDescription: String? = "BLUE BOTTLE COFFEE #12",
    merchantName: String? = "Blue Bottle",
    mcc: String? = "5814",
    foreignAmount: WalletMetadata.Money? = nil,
    foreignRate: String? = nil
) -> WalletMetadata.WalletPayload {
    WalletMetadata.WalletPayload(
        transactionId: "txn-1",
        accountId: accountId,
        accountDisplayName: "Apple Card",
        institutionName: "Goldman Sachs Bank",
        transactionDate: transactionDate,
        postedDate: postedDate,
        status: "booked",
        isPending: false,
        transactionType: transactionType,
        creditDebitIndicator: creditDebit,
        transactionDescription: description,
        originalTransactionDescription: originalDescription,
        merchantName: merchantName,
        merchantCategoryCode: mcc,
        merchantCategoryDescription: "Coffee shop",
        amount: .init(value: amount, currency: currency),
        foreignAmount: foreignAmount,
        foreignExchangeRate: foreignRate
    )
}

private func hash(_ p: WalletMetadata.WalletPayload, status: String = "posted") -> String {
    SyncEngine.contentHash(wallet: p, status: status)
}

@Suite("Content hash")
struct ContentHashTests {

    @Test("is stable within a process")
    func stable() {
        #expect(hash(makePayload()) == hash(makePayload()))
    }

    @Test("is a 64-character lowercase hex digest")
    func wellFormed() {
        let h = hash(makePayload())
        #expect(h.count == 64)
        #expect(h.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("matches the recorded digest for a known input")
    func golden() {
        // Pinned so the canonical encoding can't drift silently. If this fails,
        // every installed client will re-send its entire history on next
        // launch — so changing this value is a deliberate migration decision,
        // not a test to "fix" by pasting in whatever the new digest is.
        #expect(hash(makePayload()) == "c26a57bf73d48f213629a4e25ced63fe8c76696fb8c33d7a005a324d92c5e367")
    }

    // Each of these is a field the server needs to see corrected.
    @Test("changes when a change-relevant field changes", arguments: [
        "amount", "currency", "creditDebit", "transactionDate", "postedDate",
        "transactionType", "description", "originalDescription",
        "merchantName", "mcc", "accountId", "foreignAmount", "foreignRate"
    ])
    func detectsChange(field: String) {
        let base = hash(makePayload())
        let changed: String
        switch field {
        case "amount":              changed = hash(makePayload(amount: "42.11"))
        case "currency":            changed = hash(makePayload(currency: "EUR"))
        case "creditDebit":         changed = hash(makePayload(creditDebit: "credit"))
        case "transactionDate":     changed = hash(makePayload(transactionDate: "2026-08-03T12:00:00.000Z"))
        case "postedDate":          changed = hash(makePayload(postedDate: "2026-08-04T12:00:00.000Z"))
        case "transactionType":     changed = hash(makePayload(transactionType: "refund"))
        case "description":         changed = hash(makePayload(description: "OTHER"))
        case "originalDescription": changed = hash(makePayload(originalDescription: "OTHER"))
        case "merchantName":        changed = hash(makePayload(merchantName: "Other"))
        case "mcc":                 changed = hash(makePayload(mcc: "5999"))
        case "accountId":           changed = hash(makePayload(accountId: "acct-2"))
        case "foreignAmount":       changed = hash(makePayload(foreignAmount: .init(value: "38.20", currency: "EUR")))
        case "foreignRate":         changed = hash(makePayload(foreignRate: "1.102"))
        default:                    changed = base
        }
        #expect(changed != base, "\(field) must change the hash")
    }

    @Test("changes when pending flips to posted")
    func detectsStatusFlip() {
        #expect(hash(makePayload(), status: "pending") != hash(makePayload(), status: "posted"))
    }

    @Test("ignores fields the packet doesn't key on")
    func ignoresIrrelevant() {
        // merchantCategoryDescription is derived, not authoritative — it must
        // not by itself re-queue a row.
        var p = makePayload()
        p.merchantCategoryDescription = "Something else entirely"
        #expect(hash(p) == hash(makePayload()))
    }

    @Test("distinguishes nil from empty string")
    func nilIsNotEmpty() {
        // Without a distinct nil marker, a merchant name cleared to "" and one
        // that is absent would hash identically, and one of those two
        // corrections would never reach the server.
        #expect(hash(makePayload(merchantName: nil)) != hash(makePayload(merchantName: "")))
        #expect(hash(makePayload(mcc: nil)) != hash(makePayload(mcc: "")))
        #expect(hash(makePayload(postedDate: nil)) != hash(makePayload(postedDate: "")))
    }

    @Test("can't have values shifted across the field separator")
    func noSeparatorAmbiguity() {
        // "ab" | "c" must not collide with "a" | "bc".
        #expect(hash(makePayload(merchantName: "ab", mcc: "c"))
                != hash(makePayload(merchantName: "a", mcc: "bc")))
    }
}
