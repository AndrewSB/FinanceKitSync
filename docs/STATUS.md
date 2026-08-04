# Status

Single source of truth for where the project stands. Update the date and the
table whenever something moves.

**Last updated:** 2026-08-04

## Workstreams

| # | Workstream | Owner | State | Blocked on |
|---|---|---|---|---|
| A | [iOS app](./workstream-app.md) | Claude | 🟢 builds; untested on device | FinanceKit entitlement (device install) |
| B | [Server on `box`](./workstream-server.md) | Claude | 🟢 deployed, 13/13 protocol tests pass | Andrew: decide public exposure |
| C | [Landing page](./workstream-landing.md) | Claude | 🟡 written & pushed to `gh-pages` | Andrew: repo must be public to serve it |
| D | [Xcode Cloud](./xcode-cloud.md) / [App Store](./app-store.md) / [ASC setup](./app-store-connect-setup.md) | Andrew | 🔴 **critical path** | Eligibility — see the blocking question below |

Workstreams A and B are independent and run in parallel. C depends on both. D's
long pole (the entitlement) is independent of everything and should start now.

## Critical path

```
Confirm account type ──► (maybe: convert to Organization, weeks, D-U-N-S)
        │
        ▼
Add financial-management surface ──► app record + listing ──► entitlement
        │                                                        request
        │                                                           │
        │                              (days-to-weeks, Apple's call)│
        ▼                                                           ▼
A: iOS app ──┐                                                  approval
             ├──► verified on device ──► C: landing page ──► App Review
B: server ───┘
```

**Correction to an earlier assumption in this file:** a development build does
*not* run on a device without the entitlement. Measured — signing fails with
`Provisioning profile ... doesn't include the FinanceKit capability` and
`Entitlement com.apple.developer.financekit requires approval from Apple`. The
only way to get a build onto hardware today is the unentitled variant
(`app/Supporting/FinanceKitSync-Unentitled.entitlements`), which installs and
runs but reads no financial data. So the entitlement gates *device testing*,
not just distribution.

A and B are otherwise independent and can progress; C depends on both.

## Decisions made

| Date | Decision | Rationale |
|---|---|---|
| 2026-08-04 | Split mirror out of LunchSync into its own app | Agreed with LunchSync's owner; different audiences |
| 2026-08-04 | Name `FinanceKitSync`, bundle `com.asb.FinanceKitSync` | Apple-specific per request; display name may differ (see SPEC §2) |
| 2026-08-04 | Tailscale Funnel for server exposure | `box` is behind NAT; Funnel gives public TLS with no port forwarding |
| 2026-08-04 | Drop CloudKit, app group, keychain group, push | Single target needs none of them; fewer restricted entitlements = easier review |
| 2026-08-04 | Bearer token auth, Keychain-stored | v0 server accepted any caller that could reach it |
| 2026-08-04 | SQLite upsert replaces JSONL append | JSONL grew unbounded and couldn't answer balance queries |
| 2026-08-04 | GitHub Pages for the landing page | Free, repo-tied, no Actions `workflow` scope needed if deployed from a branch |
| 2026-08-04 | Xcode Cloud, manual + branch-triggered | Per request |

## Known risks

| Risk | Severity | Mitigation |
|---|---|---|
| FinanceKit entitlement denied or slow | **High** — blocks all distribution | File day one; the app is useful as a personal dev build regardless |
| "FinanceKit" in the App Store display name rejected | Low | Rename the listing; bundle ID and repo unaffected |
| `gh` token lacks `workflow` scope | Low | Deploy Pages from a branch folder, not an Actions workflow |
| Funnel port 8443 reclaimed by another service | Low | `box` already runs Funnel on 10000 and 3000; document the port in workstream-server.md |
| v0 `server/main.py` source lost | Resolved | Contract recovered from `.pyc`; v1 is a rewrite anyway |

## Entitlement request — filed

| | |
|---|---|
| Request ID | **`453VPT726K`** |
| Filed | 2026-08-04 |
| Version sent | **B** — the app as it stands, without financial management features |
| Bundle ID | `com.asb.FinanceKitSync` |
| Team | `A29347X2JZ` — **Individual account** (confirmed by Andrew, 2026-08-04) |

### Two independent rejection risks

1. **Account type.** Apple's FinanceKit API documentation states you must *"hold
   an organization-level Apple Developer account, be logged in as Account
   Holder."* This account is Individual.

   Note the sources conflict: <https://developer.apple.com/financekit/>, fetched
   directly, lists only two eligibility bullets (Finance category, financial
   management tools) and says requests "may be submitted by an Account Holder",
   with **no** account-type restriction. The organization requirement appears in
   the API documentation rather than the eligibility list. Unresolved from
   outside Apple.

2. **Financial management tools.** Covered below — the app doesn't provide them.

### Next action: ask Apple directly

Contact Apple Developer Support citing `453VPT726K`:

1. Does the FinanceKit entitlement require an organization-level account?
2. If so, what is the path from an Individual account — conversion, or a new
   enrolment?

This is authoritative, free, and takes a day or two. It decides whether the next
few weeks are "build features" or "form a legal entity, get a D-U-N-S number,
enrol".

> **Hold off on creating the App Store Connect app record until Support
> answers.** If a *new* organization account is required, that's a different
> Team ID, and a record created now under `A29347X2JZ` would need transferring
> or recreating.
>
> Note also: the App Store Connect API does **not** expose app-record creation,
> so that first step is manual regardless (tools like `fastlane produce` drive
> the web session with an Apple ID and password). Everything after the record
> exists — metadata, versions, TestFlight, builds — is API-automatable.

Version B was submitted knowingly, with the qualification risk below understood.
If Apple comes back citing the financial-management-tools criterion, the fix is
already scoped — see [`app-store.md`](./app-store.md) §0 — and Version A of the
explanation text in [`entitlement-request-text.md`](./entitlement-request-text.md)
is ready for a resubmit.

**Hedge while waiting:** build the Accounts + Trends surface anyway. It's needed
for App Review regardless of how this request lands, and having it done turns a
rejection into a same-day resubmit instead of a restart.

## 🔴 Open risk: does this app qualify for the entitlement at all?

Apple's published FinanceKit criteria require the app to **"provide financial
management tools (for example, a comprehensive view of net worth, spending
trends, budgeting)"**. SPEC §1 explicitly rules all of that out.

This is a product-level conflict, not a paperwork one, and it outranks
everything else on this page. Full analysis and options in
[`app-store.md`](./app-store.md) §0. Recommended fix: add an on-device
Accounts + spending-trends surface, using data the sync already reads and
currently discards.

Also unverified and potentially worse: Apple's guidance points to an
**organization-level** developer account. `A29347X2JZ` looks like an Individual
account. If conversion is required it needs a D-U-N-S number and becomes the
new critical path. **Check <https://developer.apple.com/account> → Membership
first — it's five minutes and it determines whether anything else matters.**

## Waiting on Andrew

1. **Confirm account type** (Individual vs Organization) — see above.
2. **Decide on the financial-management surface** — see above.
3. **Device test** — Andrew has an iPhone available later on 2026-08-04.
4. **Decide how the server gets exposed publicly.** Deployed and working, but
   tailnet-only; see the Funnel note in the log below.
5. **Decide whether the repo goes public.** GitHub Pages is unavailable on a
   private repo on the free plan (confirmed: HTTP 422, "Your current plan does
   not support GitHub Pages for this repository"). The `gh-pages` branch is
   pushed and will serve the moment either changes.
6. **Xcode Cloud first-run setup** — the source-control grant is an interactive
   OAuth step that can't be scripted. See [`xcode-cloud.md`](./xcode-cloud.md).

## Log

- **2026-08-04** — Repo created. Spec written. Recovered the v0 wire contract
  from `LunchSync/server/__pycache__/main.cpython-314.pyc` after finding the
  source file gone. Confirmed `box` reachable, Funnel-capable on 443/8443/10000
  with 8443 free. Confirmed local signing identity for team `A29347X2JZ`.
- **2026-08-04** — App builds clean for simulator under Swift 6 strict
  concurrency (three isolation fixes were needed; the original built in Swift 5
  mode where they didn't surface). Device signing fails on the FinanceKit
  entitlement exactly as expected, and succeeds with the unentitled variant.
  Xcode registered `com.asb.FinanceKitSync` on the developer portal during a
  provisioning run.
- **2026-08-04** — Server deployed to `box`, all 13 protocol checks pass
  (`server/test_protocol.sh`).
- **2026-08-04** — Test target added: 44 tests, all passing, including an
  opt-in end-to-end suite that drives real packets to the deployed server.
  Three real defects found by writing them:
  1. **"Test connection" accepted any token.** `checkHealth` only hit `/health`,
     which is unauthenticated by design, so a typo'd token reported "Connected"
     and failed later at first sync. Now a two-step check (`/health` then an
     authenticated `/stats`).
  2. **The app crashed on simulator.** `FinanceStore.isDataAvailable` returns
     *true* there, but the first query **traps** inside FinanceKit
     (`insufficient permission`) rather than throwing — and a trap can't be
     caught. The `isSimulator` branch skipped the availability guard and queried
     anyway. `SyncEngine` now returns `.skipped` before touching FinanceKit at
     all on simulator.
  3. Test-harness races: parallel suites clobbered each other's HTTP stubs and
     each other's global `ServerConfig`. Fixed with per-test stub hostnames and
     an async mutex (`ConfigIsolation`) — `.serialized` only orders tests
     *within* a suite.
- **2026-08-04** — Verified Apple's FinanceKit eligibility criteria against
  <https://developer.apple.com/financekit/> and found the qualification conflict
  recorded at the top of this file. Earlier assumptions in this repo about the
  entitlement being purely a paperwork step were wrong.
- **2026-08-04** — Dropped a briefly-added fastlane setup. Xcode Cloud was
  already the chosen path and handles signing, build numbers, and TestFlight
  upload natively for a single-target app with automatic signing; fastlane
  would have been a redundant second pipeline requiring an API key.
- **2026-08-04** — **Funnel incident.** Enabling Funnel on `:8443` also
  published a pre-existing `/api → 127.0.0.1:8444` route that had been
  tailnet-only, because Funnel is per-port, not per-path. Worse, `tailscale
  funnel --https=8443 off` deleted the port's *entire* serve config, taking
  that neighbouring route with it. Both were restored and the original public
  posture (Funnel on `:10000` and `:3000` only) verified via `tailscale funnel
  status`. Funnel is now opt-in in `deploy.sh` behind `FKS_ENABLE_FUNNEL=1`.
  Note also that curling a `ts.net` name from a machine on the tailnet proves
  nothing about public reachability — only `tailscale funnel status` does.
