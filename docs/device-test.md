# Device test — what's possible before the entitlement

## What you can and can't verify

Without `com.apple.developer.financekit`, a device build must be signed with the
unentitled variant. On real hardware that build behaves predictably:
`FinanceStore.isDataAvailable(.financialData)` returns **false**, so the engine
throws a clean, user-visible error instead of reading anything.

| | |
|---|---|
| ✅ Installs and launches on hardware | |
| ✅ Onboarding flow, all three steps | |
| ✅ Connection test against the real server — reachable / 401 / wrong-server / OK | |
| ✅ Settings, log view, share sheet | |
| ✅ Error handling when financial data is unavailable | should read *"Financial data isn't available on this device."*, not crash |
| ❌ Reading real transactions | needs the entitlement |
| ❌ Mapping, pagination, batching, balances | all downstream of the read |
| ❌ Background refresh doing useful work | it'll run and find nothing |

So this validates the whole app **except** the FinanceKit read — which is
genuinely most of it, and worth doing now.

## Before you start

1. **Plug the iPhone into the Mac** (or pair it for wireless debugging). As of
   the last check no physical device was connected — only simulators.
2. **Bring the phone onto the tailnet.** `box` currently serves
   `https://$FKS_HOST:8443` **tailnet-only** (see
   [Host names](workstream-server.md#host-names)), so the phone needs the
   Tailscale app connected and joined to the tailnet.
   Alternative: enable Funnel on 8443 — but read the warning in
   `server/deploy.sh` first, because that port also serves an unrelated `/api`
   route that would become public.

## Build and install

```bash
cd app
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -destination 'platform=iOS,name=<your iPhone>' \
  -configuration Debug -allowProvisioningUpdates \
  CODE_SIGN_ENTITLEMENTS=Supporting/FinanceKitSync-Unentitled.entitlements \
  build
```

Or from Xcode: select the device, then set **Build Settings → Code Signing
Entitlements** to `Supporting/FinanceKitSync-Unentitled.entitlements` for the
Debug configuration and hit Run.

> Remember to put it back to `Supporting/FinanceKitSync.entitlements` once the
> entitlement is approved. A build signed with the unentitled file silently
> reads nothing.

## Test script

Server URL: `https://box.tail590aa.ts.net:8443`
Token: `ssh box "grep '^FKS_TOKEN=' /opt/financekitsync/.env | cut -d= -f2-"`

1. **Fresh install** → onboarding step 1 renders, Continue advances.
2. **Enter a bad URL** (`http://example.com`) → footer flags it as not valid
   https, Continue stays disabled.
3. **Enter the real URL with a wrong token** → Test connection reports
   *"The server refused the token."*
   *(This is the two-step check working — `/health` alone would have said OK.)*
4. **Enter the real URL and correct token** → *"Connected"*.
5. **Turn Tailscale off on the phone, retest** → *"Couldn't reach the server…"*.
6. **Turn it back on, continue** → permission step, then Home.
7. **Tap Sync now** → expect *"Financial data isn't available on this device."*
   Not a crash, not a hang.
8. **Activity log** → shows the run and the error; Export opens a share sheet.
9. **Settings → change the server URL** → confirm it warns/clears the ledger.
10. **Force-quit and relaunch** → goes straight to Home, config persisted
    (proves the Keychain write works on real hardware, which is exactly what
    silently failed in the unsigned test host).

Anything unexpected, grab the Activity log export.

## After the entitlement lands

Re-sign with the real entitlements file and work through the device-only list in
[`workstream-app.md`](./workstream-app.md) — the read, the mapping, pagination
over >1000 rows, batching, corrections re-queueing, and background refresh.
