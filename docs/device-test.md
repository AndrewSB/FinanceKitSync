# Device test

**Run at last on 2026-08-07** — build 25 works on a real iPhone: the permission
prompt appears and the app functions. Before that, nothing in this repo had ever
run on hardware, and the cost was not theoretical: build 19 reached App Review
unable to request the Wallet permission at all, and thirty seconds on a device
would have caught it. The bulk-sync items in Part 3 are still worth working
through individually. The simulator cannot substitute — `isDataAvailable`
returns `true` there and the first real query **traps** inside FinanceKit, which
is why `SyncEngine` refuses to touch it on simulator at all.

The entitlement is live and provisioned, so the full test is available. Build
with the **real** entitlements file — `Supporting/FinanceKitSync.entitlements`,
which is what the project already uses. The unentitled variant exists only for
signing without approval and reads nothing; do not use it here.

## Before you start

1. **Plug the iPhone into the Mac**, or pair it for wireless debugging.
2. **Bring the phone onto the tailnet.** Box API exposes the FinanceKit RPC at
   `https://$FKS_HOST:8443/api/financekit`; the underlying service remains
   localhost-only on the box.
3. The account needs **real Apple Card, Apple Cash, or Apple Pay history**. A
   device with none is a valid test of "zero transactions is not an error", but
   it proves nothing about the read itself.

## Build and install

```bash
cd app
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -destination 'platform=iOS,name=<your iPhone>' \
  -configuration Debug -allowProvisioningUpdates build
```

Or select the device in Xcode and hit Run. Note the local Xcode is a 27 beta:
fine for a development build, **never** for anything submitted — see
[`releasing.md`](./releasing.md).

## Part 1 — the permission, first and above all

This is the part that has never been proven, and the part that was broken.

1. **Fresh install, walk onboarding to step 3, tap Continue.**
   → iOS must present the **financial data consent prompt**. If no prompt
   appears, stop: that is the build-19 bug returning, and the app will now say
   so on screen instead of silently continuing.
2. **Grant access.** → Onboarding completes to Home.
3. **Settings › Privacy & Security › Financial Data** → **FinanceKit Sync must
   be listed.** Its absence is the exact symptom that exposed the original bug.
4. **Revoke access there, return to the app, tap Sync now.** → a clean,
   user-visible error, not a crash and not a silent success.
5. **Re-grant, relaunch.** → sync proceeds.

## Part 2 — the app around it

Server URL: `https://$FKS_HOST:8443/api/financekit`
Token: `ssh box "grep '^FKS_TOKEN=' /opt/financekitsync/.env | cut -d= -f2-"`

1. **Enter a bad URL** (`http://example.com`) → footer flags it as not valid
   https, Continue stays disabled.
2. **Real URL, wrong token** → *"The server refused the token."*
   *(This is the two-step check working — `/health` alone would have said OK.)*
3. **Real URL, correct token** → *"Connected"*.
4. **Turn Tailscale off on the phone, retest** → *"Couldn't reach the server…"*.
5. **Activity log** → shows the run; Export opens a share sheet.
6. **Settings → change the server URL** → confirm it warns/clears the ledger.
7. **Force-quit and relaunch** → straight to Home, config persisted. (Proves the
   Keychain write works on real hardware — exactly what failed silently in the
   unsigned test host.)

## Part 3 — the read itself

The eleven items that have never been exercised, listed in
[`workstream-app.md`](./workstream-app.md): the read, the FinanceKit→packet
mapping against real data, pagination past 1000 rows, batching, corrections
re-queueing, balances, revocation handling, and background refresh.

Check the server actually received what the app claims it sent:

```bash
ssh box "sqlite3 /opt/financekitsync/data/financekitsync.db \
  'select count(*) from transactions; select count(*) from accounts;'"
```

Anything unexpected, grab the Activity log export.
