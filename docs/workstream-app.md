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
    Views/
      OnboardingView.swift
      HomeView.swift
      SettingsView.swift
      LogView.swift
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

## Verification checklist

- [ ] Builds clean for simulator
- [ ] Builds + signs for a registered device under team `A29347X2JZ`
- [ ] Onboarding "Test connection" correctly distinguishes: unreachable host,
      bad TLS, 401, 200
- [ ] Full-history backfill against the real server completes and is resumable
      if killed mid-run
- [ ] Second run sends an accounts-only packet (0 transactions)
- [ ] "Re-send everything" replays the full history
- [ ] Revoking FinanceKit access in iOS Settings produces a clear error, not a crash

## Open items

- [ ] App icon (currently a placeholder)
- [ ] QR pairing instead of typing a token (SPEC §8)
- [ ] Decide whether the simulator path stays (FinanceKit has no simulator data;
      upstream had an `isSimulator` bypass that skipped authorization)
