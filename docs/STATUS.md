# Status

Single source of truth for where the project stands.

**Last updated:** 2026-08-04
**State:** ⏸️ **PARKED — waiting on Apple.** Everything buildable is built.

---

# ⏸️ Parked: waiting on FinanceKit entitlement `453VPT726K`

Nothing further can be done until Apple responds. This is not a scoping or
effort problem — the work is finished up to a hard external gate.

**Why nothing else can proceed:** without the entitlement the app **cannot be
signed at all** for a physical device. Signing fails outright:

```
Provisioning profile "..." doesn't include the FinanceKit capability.
Entitlement com.apple.developer.financekit requires approval from Apple.
```

So there is no archive, therefore no build, therefore no TestFlight, no
screenshots from real data, and no App Store submission. The entitlement gates
**device testing**, not merely distribution.

The only build that installs today is the unentitled variant
(`app/Supporting/FinanceKitSync-Unentitled.entitlements`). It runs, and the UI
works, but `FinanceStore.isDataAvailable` returns false, so it reads zero
transactions. Useful for UI checks; useless for validating the sync.

**Considered and ruled out:** building LunchSync instead, since it already holds
the entitlement and its `feature/transaction-mirror` branch posts to a
configurable mirror URL. Blocked — that app signs under team `MF7QJ9TF5S`
(LittleBlueBug Software, LLC) and Andrew has no access to it. Only one signing
identity exists locally, for `A29347X2JZ`.

---

# ▶️ Resume here when the entitlement is approved

Work through in order. Steps 1–4 are quick; step 5 is the real work.

### 1. Switch to the real entitlements file

The repo already points at the real one — just confirm nothing is overriding it:

```bash
cd app
grep -rn "CODE_SIGN_ENTITLEMENTS" FinanceKitSync.xcodeproj/project.pbxproj
# expect: Supporting/FinanceKitSync.entitlements   (NOT ...-Unentitled...)
```

Then remove the `FKS_UNENTITLED` environment variable from **every** Xcode Cloud
workflow — see [`xcode-cloud.md`](./xcode-cloud.md). Leaving it set produces
builds that install but read nothing, which looks exactly like a broken app.

### 2. Confirm it signs

```bash
cd app
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -sdk iphoneos -destination 'generic/platform=iOS' -configuration Release \
  -allowProvisioningUpdates build
```

This currently fails. When it succeeds, the entitlement is live.

### 3. Install on the iPhone and run the device test

Full script in [`device-test.md`](./device-test.md) — 10 steps covering
onboarding, the connection check, and error handling.

Preconditions that will otherwise waste time: the phone must be **plugged in or
paired**, and **on the tailnet** (`box` serves tailnet-only), or Funnel must be
enabled on `:8443` — read the warning in `server/deploy.sh` first.

### 4. Work the device-only verification list

[`workstream-app.md`](./workstream-app.md) → *"Not verified, and not verifiable
without the entitlement."* Eleven items: the read itself, the FinanceKit→packet
mapping against real data, pagination past 1000 rows, batching, corrections
re-queueing, balances, revocation handling, background refresh.

**This is the genuinely unproven half of the project.** Everything else has
tests; none of this does.

### 5. Finish the App Store submission

Live state as of parking — verified against the API, not assumed:

| | |
|---|---|
| App record | `6797988167`, version 1.0, `PREPARE_FOR_SUBMISSION` |
| Listing metadata | ✅ complete (name, subtitle, categories, description, keywords, promo text) |
| Privacy / support / marketing URLs | ✅ set and serving |
| Builds uploaded | **0** |
| Screenshot sets | **0** |
| Privacy nutrition labels | **not started** |
| Submission record | none |

Remaining:

- **Screenshots** — 6.9" and 6.5". Plan in [`app-store.md`](./app-store.md) §5.
  Use synthetic data, not your own transactions.
- **Privacy nutrition labels** — guidance in [`app-store.md`](./app-store.md) §3.
  The honest answer is "no data collected".
- **Upload a build** — Xcode Cloud `Release` workflow, or archive locally.
- **Review notes** — [`app-store.md`](./app-store.md) §4. Stand up a *throwaway*
  server with synthetic data for App Review; do not give them `box`'s token.
- **Submit.**

### Also still open (independent of the entitlement)

- **Account type.** `A29347X2JZ` is **Individual**; Apple's FinanceKit docs point
  to organization-level. Conversion costs **$0 extra** (same $99/yr, no separate
  fee) and the D-U-N-S number is already in hand. Ask Developer Support — draft
  below. **If this turns out to be required, it invalidates `453VPT726K` and
  becomes the new critical path, so it is worth asking even while parked.**
- **Server exposure.** Deployed but tailnet-only. Funnel is per-port and `:8443`
  also serves an unrelated `/api` route — see `server/deploy.sh`.
- **Landing page copy** still says "FinanceKitSync"; the App Store name is now
  **FinanceKit Sync**.
- **Tailnet hostname is in git history** (4 commits) and the repo is public.
  Assessed as low risk — a `ts.net` name needs tailnet membership to reach, and
  Funnel is off for that port. Revisit if Funnel is ever enabled on `:8443`.

---

## Workstreams

| # | Workstream | Owner | State | Blocked on |
|---|---|---|---|---|
| A | [iOS app](./workstream-app.md) | Claude | 🟢 builds, 44 tests pass; **unproven on device** | Entitlement |
| B | [Server on `box`](./workstream-server.md) | Claude | 🟢 deployed, 13/13 protocol checks | — (exposure decision open) |
| C | [Landing / privacy / support](./workstream-landing.md) | Claude | 🟢 live on GitHub Pages | — (copy says old name) |
| D | [Xcode Cloud](./xcode-cloud.md) | Claude | 🟢 connected, `ci_scripts` ready | Workflows unbuilt; Archive fails until entitlement |
| E | [App Store](./app-store.md) / [listing](./listing.md) | Andrew | 🟡 metadata done, no build | 🔴 **Entitlement `453VPT726K`** |

## Decisions made

| Date | Decision | Rationale |
|---|---|---|
| 2026-08-04 | Split mirror out of LunchSync into its own app | Agreed with LunchSync's owner; different audiences |
| 2026-08-04 | App Store display name **FinanceKit Sync** | FinanceKit is absent from Apple's published trademark list while every sibling framework is registered. Risk accepted: worst case is a metadata rejection, fixable same-day without a new build |
| 2026-08-04 | Tailscale Funnel for server exposure | `box` is behind NAT; Funnel gives public TLS with no port forwarding |
| 2026-08-04 | Drop CloudKit, app group, keychain group, push | Single target needs none of them; fewer restricted entitlements = easier review |
| 2026-08-04 | Bearer token auth, Keychain-stored | v0 server accepted any caller that could reach it |
| 2026-08-04 | SQLite upsert replaces JSONL append | JSONL grew unbounded and couldn't answer balance queries |
| 2026-08-04 | Repo public; GitHub Pages for landing/privacy/support | Pages needs a public repo on the free plan, and the listing's "open source" claim has to resolve |
| 2026-08-04 | Removed the dead `andrewsb.me` Pages custom domain | It no longer resolved, and was 301ing every project page into a dead host |
| 2026-08-04 | No fastlane | Xcode Cloud already covers signing, build numbers, and upload for a single-target app; fastlane would be a redundant second pipeline needing an API key |
| 2026-08-04 | Listing managed as code (`tools/listing.json`) | Version-controlled and re-appliable instead of retyped into a web form |
| 2026-08-04 | Xcode Cloud, manual + branch-triggered | Per request |

## Known risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Individual account disqualifies the request** | **High** — would invalidate `453VPT726K` | Ask Developer Support now. Conversion costs $0 extra and the D-U-N-S is in hand, but it takes weeks, so learning this early matters |
| Entitlement denied or slow | **High** — blocks everything, including device testing | Filed 2026-08-04. No mitigation exists: a dev build cannot be signed without it either (this was previously — wrongly — listed as mitigated) |
| "FinanceKit" in the display name rejected | Low | Rename the listing; bundle ID, repo, and build all unaffected. Fixable same-day, no new binary |
| Funnel port 8443 reclaimed, or its `/api` route exposed | Low–Medium | Funnel is per-port, not per-path. `deploy.sh` keeps it opt-in behind `FKS_ENABLE_FUNNEL=1` |
| Tailnet hostname in public git history | Low | Requires tailnet membership to reach; Funnel off for that port. Revisit if Funnel is enabled on `:8443` |
| Reused/mismatched privacy policy | Resolved | Written fresh and verified against actual app behaviour, including the activity log's account names |
| `gh` token lacks `workflow` scope | Resolved | Pages deploys from a branch, no Actions workflow needed |
| v0 `server/main.py` source lost | Resolved | Contract recovered from `.pyc` and archived in `docs/archive/`; v1 is a rewrite |

## Entitlement request — filed

| | |
|---|---|
| Request ID | **`453VPT726K`** |
| Filed | 2026-08-04 |
| Version sent | **B** — the app as it stands, without financial management features |
| Bundle ID | `com.asb.FinanceKitSync` |
| Team | `A29347X2JZ` — **Individual account** (confirmed by Andrew, 2026-08-04) |

### Evidence from a known approval: LunchSync

<https://apps.apple.com/us/app/lunch-sync/id6739702427> — shipping, Finance
category, FinanceKit entitlement approved.

| | |
|---|---|
| Seller | **LittleBlueBug Software, LLC** → an **Organization** account |
| Category | Finance |
| Description | *"A way to sync transactions from your Apple Card or other Wallet accounts to your Lunch Money account. Select one or more wallet accounts to sync. Pair each one with an Asset from your Lunch Money account. Set it and forget it!"* |
| Financial management features | **None.** No net worth, balances, trends, or budgeting — all of that lives in Lunch Money, a separate app. |

This cuts both ways, and it reverses part of the earlier assessment in this file:

- **The financial-management-tools criterion is applied loosely.** A pure
  sync/export tool with no analysis features holds this entitlement today. The
  earlier conclusion here — that FinanceKitSync's product shape likely
  disqualifies it — was **too pessimistic**, and the recommendation to build an
  Accounts + Trends surface *in order to qualify* is withdrawn. Those screens
  are still worth building on product merit, but they are not the gate.
- **The organization requirement looks more real, not less.** The single
  approval we can observe belongs to an LLC. That's one data point, not proof,
  but it points the same way as Apple's API documentation.

Net: risk has shifted almost entirely onto the **account type**.

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

### Converting Individual → Organization

Apple supports converting an existing membership rather than enrolling a second
one. Confirmed 2026-08-04:

| | |
|---|---|
| Cost | **No separate conversion fee.** The membership is $99/year for both Individual and Organization — you are not charged twice. |
| Caveat | Apple doesn't refund the unused portion of the current Individual year. So the real cost is $0 extra, not $200. |
| Requirements | Submit a request to Apple; be the organization's **founder or co-founder**; supply the **D-U-N-S number** |
| Andrew's status | D-U-N-S number **already in hand** |

The open question is whether conversion **preserves Team ID `A29347X2JZ`**. If it
does, nothing built so far moves: the bundle ID, the App Store Connect record
(created 2026-08-04), and possibly the pending entitlement request all carry
over. If instead Apple requires a fresh enrolment, the bundle ID and app record
have to be transferred. Ask explicitly — it's the difference between zero
rework and a migration.

### Next action: ask Apple directly

Contact Apple Developer Support. Draft:

> My FinanceKit entitlement request `453VPT726K` (Team ID `A29347X2JZ`, bundle
> ID `com.asb.FinanceKitSync`) is currently filed under an Individual account.
>
> 1. Does the FinanceKit entitlement require an organization-level membership?
> 2. If so, I would like to convert my existing Individual membership to an
>    Organization membership. I have a D-U-N-S number and am the founder of the
>    entity. What do you need from me?
> 3. Does that conversion preserve my Team ID, bundle identifiers, and existing
>    App Store Connect app records — or will they need to be transferred?
> 4. Will request `453VPT726K` remain valid through the conversion, or should I
>    re-file it afterwards?

Questions 3 and 4 are the ones that decide how much rework there is. Free,
authoritative, a day or two.

> **App Store Connect record: created 2026-08-04** under `A29347X2JZ`. If
> conversion preserves the Team ID this needs no action; otherwise it gets
> transferred. Andrew has confirmed he's fine either way.
>
> Note: the App Store Connect API does **not** expose app-record creation, so
> that first step is manual regardless (tools like `fastlane produce` drive the
> web session with an Apple ID and password). Everything after the record
> exists — metadata, versions, TestFlight, builds — is API-automatable.

Version B was submitted knowingly, with the qualification risk below understood.
If Apple comes back citing the financial-management-tools criterion, the fix is
already scoped — see [`app-store.md`](./app-store.md) §0 — and Version A of the
explanation text in [`entitlement-request-text.md`](./entitlement-request-text.md)
is ready for a resubmit.

**Hedge while waiting:** build the Accounts + Trends surface anyway. It's needed
for App Review regardless of how this request lands, and having it done turns a
rejection into a same-day resubmit instead of a restart.

## Qualification risk — assessed, mostly retired

Apple's published criteria require the app to *"provide financial management
tools (for example, a comprehensive view of net worth, spending trends,
budgeting)"*, which this app deliberately does not do. That looked like a hard
disqualifier, and this file previously recommended building an Accounts +
spending-trends surface in order to qualify.

**That recommendation was withdrawn.** LunchSync
(<https://apps.apple.com/us/app/lunch-sync/id6739702427>) holds this entitlement
while describing itself purely as a sync tool with no analysis features at all.
So the criterion is applied loosely, and this app's shape is not the problem it
appeared to be. Those screens remain worth building on product merit — not to
satisfy Apple.

What the same evidence *did* strengthen: LunchSync's seller is **LittleBlueBug
Software, LLC**, an Organization account. Combined with Apple's FinanceKit API
documentation requiring organization-level membership, the account-type question
is now where essentially all the remaining risk sits.

## Waiting on Andrew

Only one thing is worth doing while parked:

**Ask Apple Developer Support about the account type.** Free, a day or two, and
it could invalidate `453VPT726K` — better to learn that now than after a
multi-week wait. Draft is above under *"Entitlement request — filed"*.

Everything else is either done or gated on Apple. See
*"Resume here when the entitlement is approved"* at the top of this file.

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
- **2026-08-04** — App Store Connect record created (`6797988167`) and the full
  listing applied via the API from `tools/listing.json`: name **FinanceKit
  Sync**, subtitle, Finance/Utilities categories, description, keywords,
  promotional text, and privacy/support/marketing URLs. Verified by reading it
  back. Two API constraints found the hard way: `apps` does not allow `CREATE`
  (so the record itself must be made in the web UI), and `whatsNew` cannot be
  set before a first release.
- **2026-08-04** — Privacy policy and support page written and published to
  GitHub Pages. Repo made public — required for Pages on the free plan, and the
  listing's "open source" claim needs to resolve. Git history scanned for
  secrets first (clean). The account-level Pages custom domain `andrewsb.me` had
  stopped resolving and was 301ing every project page into a dead host; removed
  it at Andrew's request, so the personal site is back on `andrewsb.github.io`.
- **2026-08-04** — **Parked.** No path exists to real transaction data without
  the entitlement: signing fails outright, and the fallback of building
  LunchSync (which holds the entitlement) is blocked by having no access to team
  `MF7QJ9TF5S`. All non-device work is complete.
- **2026-08-04** — **Funnel incident.** Enabling Funnel on `:8443` also
  published a pre-existing `/api → 127.0.0.1:8444` route that had been
  tailnet-only, because Funnel is per-port, not per-path. Worse, `tailscale
  funnel --https=8443 off` deleted the port's *entire* serve config, taking
  that neighbouring route with it. Both were restored and the original public
  posture (Funnel on `:10000` and `:3000` only) verified via `tailscale funnel
  status`. Funnel is now opt-in in `deploy.sh` behind `FKS_ENABLE_FUNNEL=1`.
  Note also that curling a `ts.net` name from a machine on the tailnet proves
  nothing about public reachability — only `tailscale funnel status` does.
