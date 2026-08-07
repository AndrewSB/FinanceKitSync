# Workstream A — iOS app

## Target

| | |
|---|---|
| Product | `FinanceKitSync` |
| Bundle ID | `com.asb.FinanceKitSync` |
| Team | `A29347X2JZ` (Andrew Breckenridge) |
| Deployment target | iOS 18.0 |
| Xcode | 27.0 |
| Project format | objectVersion 77, file-system-synchronized groups |

iOS 18 rather than 26: FinanceKit's `foreignCurrencyExchangeRate` needs 18, and
nothing in the app needs anything newer. A lower floor is free reach.

## Project layout

```
app/
  FinanceKitSync.xcodeproj
  FinanceKitSync/
    FinanceKitSyncApp.swift        app entry, BGTask registration
    Sync/
      SyncEngine.swift             ported from MirrorSyncEngine
      SyncLedger.swift             ported from MirrorLedger
      SyncAPI.swift                ported from MirrorAPI (+ bearer auth)
      WalletMetadata.swift         ported verbatim
      SyncCoordinator.swift        observable state for the UI
    Storage/
      ServerConfig.swift           URL in UserDefaults, token in Keychain
      Keychain.swift
      LogStore.swift
    Purchases/
      Entitlement.swift            may this install sync in the background?
      SubscriptionStore.swift      product, purchase, restore, Transaction.updates
    Views/
      OnboardingView.swift
      HomeView.swift
      SettingsView.swift
      PaywallView.swift
      LogView.swift
    FinanceKitSync.storekit        local StoreKit config (scheme-referenced)
    Info.plist
    FinanceKitSync.entitlements
    Assets.xcassets
```

The Xcode project uses **file-system-synchronized root groups**
(`PBXFileSystemSynchronizedRootGroup`, Xcode 16+). Adding a `.swift` file to the
folder adds it to the target — no `project.pbxproj` edit, so no merge conflicts
on the one file that always conflicts.

## Entitlements

```xml
<key>com.apple.developer.financekit</key>
<array><string>financial-data</string></array>
```

That is the whole file. Deliberately: see SPEC §3.2 for what was dropped and why.

`Info.plist` needs `NSFinancialDataDescription` (App Review reads it) and
`BGTaskSchedulerPermittedIdentifiers`.

## Port notes

Straight lifts from `LunchSync/LMPlayground/Mirror/`, with these changes:

- `MirrorAPI.sync` gains an `Authorization: Bearer` header; the path moves to
  `/financekit-sync`.
- `MirrorLedger` drops the app-group container and writes to the app's own
  Application Support directory.
- `MirrorSyncEngine.RunLock` (the `flock` cross-process guard) is **deleted** —
  with the background extension gone there is only one process. An in-process
  actor prevents a foreground tap from racing a background task.
- `isBackgroundExtension` detection is deleted for the same reason.
- Everything about hashing, pagination, and batching is preserved exactly. Those
  behaviours were hardened over several review passes upstream and the reasoning
  is captured in SPEC §3.1 — do not "simplify" them without reading that first.

## What is actually verified

Be precise about this. "It builds" is not "it works", and the server's protocol
tests exercise the *server*, with none of the Swift code in the loop.

### Verified

- [x] Builds clean for simulator under Swift 6 strict concurrency
- [x] Signs for device with the unentitled variant
- [x] Launches on simulator; onboarding renders and is navigable
- [x] Unit tests pass — content hash, URL validation, ledger diff/upsert/reset,
      packet encoding, receipt decoding, HTTP error mapping
- [x] The content hash is pinned to a recorded digest, so the canonical
      encoding can't drift silently and re-send everyone's history
- [x] The ledger persists only `id`, `contentHash`, `mirroredAt` — asserted
      against SwiftData's schema, because the landing page and the App Store
      listing both make this claim
- [x] Simulator behaviour pinned: `FinanceStore.isDataAvailable(.financialData)`
      returns **true** there, but the first real query **traps** inside
      FinanceKit (`insufficient permission`) rather than throwing. A trap can't
      be caught, so `SyncEngine` bails out with `.skipped` before touching
      FinanceKit at all on simulator (`FinanceKitAvailabilityTests`)
- [x] End-to-end against the real server: packet encode → bearer auth → TLS →
      HTTPS POST → server upsert → receipt decode, plus idempotent replay,
      correction-updates-in-place, and the 401 path (`EndToEndTests`, opt-in via
      `TEST_RUNNER_FKS_TEST_URL` / `TEST_RUNNER_FKS_TEST_TOKEN`)

### Not verified, and not verifiable without the entitlement

Everything below needs a physical iPhone with real Apple Card / Apple Pay
history **and** an approved FinanceKit entitlement. A simulator's FinanceKit
store is permanently empty, so no amount of local testing substitutes.

- [ ] Real transactions are read at all
- [ ] The FinanceKit → packet mapping is correct against real data
      (sign flip on credits, posted/pending, MCC, foreign amounts)
- [ ] Full-history pagination across >1000 rows
- [ ] Full-history backfill completes, and resumes correctly if killed mid-run
- [ ] Batching at 500/packet against a real multi-thousand-row history
- [ ] A correction (amount change, pending→posted) actually re-queues its row
- [ ] Second run sends an accounts-only packet (0 transactions)
- [ ] "Re-send everything" replays the full history
- [ ] Account balances are read correctly
- [ ] Revoking access in iOS Settings produces a clear error, not a crash
- [ ] Background refresh fires and completes

This list is the real definition of done for workstream A. Nothing on it can be
ticked before the entitlement lands.

## Running the tests

```bash
cd app

# Unit tests
xcodebuild test -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Including the end-to-end suite (skipped without these).
# $FKS_HOST — see docs/workstream-server.md#host-names
export TEST_RUNNER_FKS_TEST_URL="https://$FKS_HOST:8443"
export TEST_RUNNER_FKS_TEST_TOKEN=$(ssh box "grep '^FKS_TOKEN=' /opt/financekitsync/.env | cut -d= -f2-")
xcodebuild test -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Two things that cost time here, both worth not rediscovering:

- **Do not pass `CODE_SIGNING_ALLOWED=NO`.** An unsigned test host has no
  `application-identifier` entitlement, so every Keychain write fails —
  `ServerConfig.token` reads back as nil and tests fail with a misleading
  `.notConfigured`. Simulator signing is free; just let it happen.
- **Getting environment variables into the test process needs the
  `TEST_RUNNER_` prefix.** The host runs inside the simulator and inherits
  neither your shell environment nor build settings — so plain `export
  FKS_TEST_URL=…` and `xcodebuild FKS_TEST_URL=…` both silently do nothing, and
  the suite just reports itself skipped. `xcodebuild` forwards any
  `TEST_RUNNER_`-prefixed variable to the runner with the prefix stripped.
  (Declaring them in the scheme as `$(FKS_TEST_URL)` doesn't work either —
  build-setting expansion isn't applied there.)

## Open items

- [ ] App icon — generated by `app/Supporting/make-icon.swift`; serviceable,
      not designed
- [ ] QR pairing instead of typing a token (SPEC §8)
- [x] ~~Decide whether the simulator path stays~~ — **resolved, opposite to the
      first answer.** An earlier note here claimed the simulator returns an empty
      result set rather than trapping. That was wrong: the test asserting it
      never reached a query. Measured properly, `isDataAvailable` returns *true*
      but the first query **traps** — which killed the whole test process. The
      `isSimulator` branch now returns `.skipped` before any FinanceKit call, so
      the simulator can't crash the app. Pinned by `FinanceKitAvailabilityTests`,
      which deliberately contains **no** test that calls into `FinanceStore`.
