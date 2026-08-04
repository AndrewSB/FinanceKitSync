# FinanceKitSync — Product & Technical Spec

**Status:** draft v1
**Owner:** Andrew Breckenridge (Apple Team `A29347X2JZ`)
**Derived from:** the `Mirror` module in [`AndrewSB/LunchSync`](https://github.com/AndrewSB/LunchSync) (branch `feature/transaction-mirror`)

---

## 1. What this is

An iPhone app that reads your Apple Card / Apple Pay / Apple Cash transaction
history out of **FinanceKit** and mirrors it to **a server you control**. That is
the entire product. There is no hosted backend, no account, no third-party
service in the path, and no vendor that ever sees your financial data.

The upstream project (LunchSync) syncs FinanceKit into Lunch Money, a specific
budgeting SaaS. The mirror capability grew inside it as an optional side channel.
It is being split out because the two products have genuinely different
audiences: LunchSync's user wants a turnkey integration with one service;
FinanceKitSync's user wants a raw, complete, self-hosted feed they can build
anything on top of.

### Non-goals for v1

- No budgeting, categorization, charts, or analytics in the app.
- No hosted/managed server offering. Users bring their own endpoint.
- No Android, no Mac, no web app.
- No multi-user or family sharing.
- No transformation of the data. The app ships FinanceKit's fields through
  faithfully and lets the server decide what to do with them.

---

## 2. Why it can exist at all (and the main risk)

`com.apple.developer.financekit` with the `financial-data` capability is a
**restricted entitlement**. It requires:

1. A paid Apple Developer Program membership, and
2. A separate written request to Apple, approved per–Team ID and per–bundle ID.

This is the critical path for the entire project — it gates App Store review and
cannot be parallelized away. The entitlement request must be filed on day one.
See [`app-store.md`](./app-store.md) for the request text.

The upstream LunchSync app holds this entitlement under team `MF7QJ9TF5S`
(littlebluebug). **That approval does not transfer.** FinanceKitSync needs its
own approval under `A29347X2JZ` for bundle ID `com.asb.FinanceKitSync`.

> **Naming caveat:** App Review discourages App Store *display names* built from
> Apple technology names. `FinanceKitSync` is safe as the repo name, Xcode
> project name, and bundle ID, but the customer-facing name on the store listing
> should probably differ (e.g. "Ledgerline", "Card Mirror"). This costs nothing
> to change later and is tracked in [`app-store.md`](./app-store.md).

---

## 3. Architecture

```
┌─────────────────────────┐         ┌──────────────────────────────────┐
│   iPhone                │         │   Your server (box)              │
│                         │         │                                  │
│  FinanceKit store       │         │   Tailscale Funnel (public TLS)  │
│         │               │         │            │                     │
│         ▼               │         │            ▼                     │
│  SyncEngine ── diff ──► │  HTTPS  │   FastAPI /financekit-sync       │
│         │      vs       │ ──────► │            │                     │
│         ▼    local      │  bearer │            ▼                     │
│  SyncLedger (SwiftData) │  token  │   SQLite (idempotent upsert)     │
└─────────────────────────┘         └──────────────────────────────────┘
```

The phone is the only thing that ever reads FinanceKit. The server is a dumb,
append-mostly sink. All intelligence about *what changed* lives on the device.

### 3.1 Sync algorithm

Carried over from `MirrorSyncEngine`, which is already correct and hardened:

1. Acquire FinanceKit authorization (`FinanceStore.requestAuthorization()`).
2. Fetch **all** accounts + their latest balances.
3. Fetch the **entire** transaction history, paginated at 1000/page, sorted by
   `(transactionDate, id)` so page boundaries are stable across runs.
4. For each transaction compute a **SHA-256 content hash** over the
   change-relevant fields (amount, currency, credit/debit, dates, status, type,
   descriptions, merchant name/MCC, foreign amount/rate, account).
5. Diff against the local `SyncLedger`; send anything unseen or whose hash moved.
6. POST in batches of 500. Stop on first failure — unacknowledged rows retry next
   run. Acknowledge each batch into the ledger only after a 2xx.
7. If nothing changed, still send one accounts-only packet so balances stay fresh.

Properties worth preserving explicitly:

- **Pagination progress guarantee.** A page contributing zero *new* ids ends the
  loop. This survives a server that ignores/clamps `offset` or repeats a page,
  which would otherwise spin forever and grow the array without bound.
- **Hash is SHA-256, not `Hashable`.** Swift's `Hasher` seed is randomized per
  process, so `hashValue` would re-send the entire history on every launch.
- **`nil` encodes distinctly from `""`** in the canonical hash string, via a
  `\u{1}nil` marker.
- **A lost ledger write is safe.** The server upserts, so a failed acknowledge
  costs one redundant resend, never a lost transaction.

### 3.2 Deliberate simplifications vs. the LunchSync original

| LunchSync (mirror module) | FinanceKitSync | Why |
|---|---|---|
| App group + separate `BackgroundHandler` extension | Single app target | No second process, so no shared container needed |
| `flock`-based cross-process `RunLock` | Removed; in-process actor guard | Only one process touches the ledger now |
| CloudKit + iCloud container entitlement | Removed | Ledger was already `cloudKitDatabase: .none`; the entitlement was dead weight and one more thing for review to question |
| Keychain access group | Removed | Single target |
| Push-triggered sync via `PushAPI` | `BGTaskScheduler` only | Removes a third-party push service from a financial-data app's threat model |
| Unauthenticated POST | Bearer token, Keychain-stored | The old server accepted anything that could reach it |
| Server appends to `received_packets.jsonl` | SQLite with idempotent upsert | JSONL grows without bound and can't answer "what's my balance" |

The reduced entitlement set is a real review advantage: v1 ships with exactly
one restricted entitlement instead of four capabilities.

---

## 4. The app

### 4.1 Screens

**Onboarding (first launch)**
1. *What this does* — one screen, plain language: your transactions are read on
   this device and sent only to the server address you enter. Nothing else
   receives them.
2. *Connect your server* — text field for base URL (https required) and bearer
   token. A "Test connection" button hits `GET /health` and shows the result
   before anything is saved.
3. *Grant access* — triggers the FinanceKit permission sheet. Explains that
   iOS, not the app, controls this and it can be revoked in Settings.

**Home**
- Connection state: server host, last successful sync, last error if any.
- Counts: accounts mirrored, transactions acknowledged, transactions pending.
- "Sync now" button with live progress ("sent 1500/4200").
- Recent activity list, newest first.

**Settings**
- Server URL + token (re-test, rotate, clear).
- Background sync toggle.
- "Re-send everything" — clears the ledger so the next run replays full history.
  Guarded by a confirmation; useful after a server rebuild.
- Export logs (share sheet) for debugging.
- Privacy statement + link to the landing page.

### 4.2 Data flow rules

- The bearer token lives in the **Keychain**, never in `UserDefaults`.
- The server URL lives in `UserDefaults` (not secret, and useful in logs).
- The ledger stores **only** `(financekit_id, content_hash, mirrored_at)` — no
  amounts, no merchants. If the device DB leaks it reveals nothing.
- Logs redact amounts and merchant names by default.
- `NSFinancialDataDescription` must state the purpose plainly; App Review reads
  this string.

### 4.3 Background sync

`BGAppRefreshTask` for the common case, `BGProcessingTask` for the initial
full-history backfill (which can be thousands of rows and wants to run on
charger + Wi-Fi). iOS decides when these run; the app must not promise real-time.

---

## 5. Wire protocol

`POST {base}/financekit-sync`
`Authorization: Bearer {token}`
`Content-Type: application/json`

```jsonc
{
  "schema_version": 1,
  "accounts": [
    { "id": "UUID", "name": "Apple Card", "institution": "Goldman Sachs Bank",
      "balance": 1234.56, "currency": "USD" }
  ],
  "transactions": [
    {
      "id": "UUID",                    // FinanceKit transaction id — the idempotency key
      "account_id": "UUID",
      "date": "2026-08-01T12:00:00.000Z",
      "amount": -42.10,                // sign-flipped for credits
      "currency": "USD",
      "payee": "BLUE BOTTLE COFFEE",
      "status": "posted",              // posted | pending
      "notes": "booked",
      "category": "5814",              // raw MCC
      "metadata": { /* full FinanceKit capture, see WalletMetadata */ }
    }
  ]
}
```

Response `200`:
```json
{ "accounts_received": 3, "transactions_received": 500,
  "transactions_inserted": 480, "transactions_updated": 20 }
```

Errors: `401` bad/missing token, `413` packet too large, `422` schema mismatch,
`5xx` server fault. The app treats every non-2xx as "retry this batch next run".

`schema_version` is sent on every packet. The server rejects versions it does not
know rather than guessing.

### 5.1 Changes from the recovered v0 server

The original `server/main.py` was never committed and its source is gone — only
`__pycache__/main.cpython-314.pyc` survived. The contract above was recovered
from that bytecode. Differences in v1:

- Path renamed `/finance-kit-sync` → `/financekit-sync` (consistency).
- Bearer auth added (v0 accepted any caller that could reach the port).
- SQLite upsert replaces unbounded JSONL append.
- Response body reports insert/update counts so the app can surface real numbers.

---

## 6. Server

Python 3.12 + FastAPI + SQLite (WAL). Deployed to `box` under Docker, fronted by
Tailscale Funnel for public TLS. No inbound port forwarding, no certificate
management, no reverse proxy to configure.

Schema:

```sql
CREATE TABLE accounts (
  id TEXT PRIMARY KEY, name TEXT, institution TEXT,
  balance REAL, currency TEXT, updated_at TEXT
);
CREATE TABLE transactions (
  id TEXT PRIMARY KEY, account_id TEXT, date TEXT, amount REAL,
  currency TEXT, payee TEXT, status TEXT, notes TEXT, category TEXT,
  metadata TEXT, first_seen_at TEXT, updated_at TEXT
);
```

`INSERT ... ON CONFLICT(id) DO UPDATE` makes replays free, which is what lets the
client treat a lost ledger write as harmless.

Full deployment detail: [`workstream-server.md`](./workstream-server.md).

---

## 7. Threat model

**In scope**
- *Network attacker.* TLS is mandatory; the app refuses non-https URLs. Funnel
  terminates with a real Let's Encrypt cert.
- *Anyone who finds the public Funnel URL.* Bearer token required on every
  request; the endpoint is otherwise unauthenticated and world-reachable.
- *Device compromise.* Token in Keychain; ledger holds no financial values.
- *Server compromise.* Contains full transaction history — this is the user's own
  risk to accept, and the landing page must say so explicitly.

**Out of scope**
- A malicious server operator (the user *is* the operator).
- Apple-level compromise of FinanceKit itself.

**Explicitly not done**
- No transport-level pinning (the user's server, the user's cert).
- No end-to-end encryption on top of TLS — the server needs plaintext to be
  useful, so this would be theater.

---

## 8. Open questions

- [ ] App Store display name, pending the "FinanceKit" naming caveat in §2.
- [ ] Does the entitlement request need a working demo build attached? (Apple has
      asked for this on some financial-data requests.)
- [ ] Should v1 ship a QR-code pairing flow instead of typing a token on a phone
      keyboard? Strong UX win; deferred to v1.1 unless the entitlement wait gives
      us free time.
- [ ] Retention policy on the server — unbounded by default, but the landing page
      should recommend backups.
