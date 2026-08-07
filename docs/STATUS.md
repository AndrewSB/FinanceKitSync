# Status

Single source of truth for where the project stands.

**Last updated:** 2026-08-07
**State:** 🟢 **Works on device, and in review.** Version 1.0 (**build 25**) is
`WAITING_FOR_REVIEW` as of 2026-08-07 02:55 UTC, submission
`f3daf509-6a74-4f57-8ffe-d93c2328b545`, carrying the
`NSFinancialDataUsageDescription` fix. The build-19 submission (`de454c50-…`)
was cancelled to make room for it.

**Andrew confirmed the app working on a real iPhone on 2026-08-07** — the first
time it has ever run on hardware. That closes the project's largest open
question: the permission prompt appears and the app functions. The itemised
checks in [`workstream-app.md`](./workstream-app.md) (pagination past 1000 rows,
corrections re-queueing, background refresh) have not been individually
confirmed and stay unticked.

---

# ✅ Fixed — build 19 could not request the Wallet permission

`Info.plist` declared **`NSFinancialDataDescription`**. The key iOS reads is
**`NSFinancialDataUsageDescription`** — the only spelling anywhere in the iOS
27.0 SDK. With no recognized usage description iOS never shows the consent
prompt, `requestAuthorization()` never returns `.authorized`, and the app never
appears under Settings › Privacy & Security › Financial Data at all. Reported by
Andrew on 2026-08-06 from exactly that symptom: the app was missing from the
list.

Everything else was right the whole time — the entitlement, the capability on
the App ID, the profile, and both `requestAuthorization()` call sites. One
misspelled key made all of it moot.

**Where the typo came from:** both drafts in
[`archive/entitlement-request-text.md`](./archive/entitlement-request-text.md),
written 2026-08-04, state *"NSFinancialDataDescription is set in Info.plist."*
The wrong name was in this repo before the plist was ever written, and it was
told to Apple in the entitlement request itself. Nothing downstream could catch
it, because nothing downstream reads that key except iOS on a real device.

**Why it survived provisioning, upload, and submission:** onboarding called
`_ = try? await FinanceStore.shared.requestAuthorization()`, discarding the
status *and* the error. A build that could never be granted access looked
exactly like one that was. Fixed in `8168eec`, which now reports a
non-`.authorized` status, links to Settings, and still lets the user continue.

Both are on `main`. Verified: Release device build signs, the correct key is in
the built `Info.plist`, tests pass 44/44 — and, on 2026-08-07, the fixed build
confirmed working on a real iPhone. That last check is the one that would have
caught this in thirty seconds, and it had never been run.

## How build 19 was replaced — done 2026-08-07

Its submission could not have the build swapped (Apple freezes a queued
submission), so the fix meant cancelling `de454c50-…` and submitting fresh,
forfeiting that queue position. Done via the API:

1. `POST /v1/ciBuildRuns` triggered the `Release` workflow on `main` — run 25,
   `SUCCEEDED` in ~5 minutes, uploading **build 25**. (Build numbers come from
   `$CI_BUILD_NUMBER`, the per-workflow run counter, hence 25 rather than 20.)
2. `tools/submit_for_review.py --build 25 --replace-queued` cancelled the old
   submission, attached build 25, and submitted `f3daf509-…`.

**MEASURED, and the reason that script grew a wait loop:** cancelling returns
200 immediately, but the version sits in `WAITING_FOR_REVIEW` for a few seconds
before settling into `DEVELOPER_REJECTED`, and attaching during that window
fails `409 INVALID_STATE`. It happened on the first run here. Re-running fixed
it, but unattended that sequence would have cancelled the old submission and
then left *nothing* queued — `ci_post_xcodebuild.sh` fails soft, so it would
have exited green having dropped the release on the floor. The script now waits
for the version to become editable before attaching.

---

# ✅ The entitlement is live

Apple approved it, but approval alone changed nothing — **the request being
granted does not enable the capability on the App ID.** FinanceKit is a
restricted entitlement, and Xcode's automatic signing will not turn those on for
you the way it does Push or App Groups. It just keeps minting profiles from
whatever the App ID already has, which is why signing kept failing with the same
error after approval, on a profile regenerated minutes earlier.

The fix was one checkbox: **Certificates, Identifiers & Profiles → Identifiers →
`com.asb.FinanceKitSync` → Additional Capabilities → FinanceKit → Save.** Then
delete the cached profile in `~/Library/Developer/Xcode/UserData/Provisioning
Profiles/` and rebuild, so Xcode fetches a fresh one instead of reusing the
stale one.

Verified end to end on 2026-08-06 — the signed binary carries:

```
"com.apple.developer.financekit" => [ 0 => "financial-data" ]
```

# ▶️ Where things actually stand

| | |
|---|---|
| App record | `6797988167`, version 1.0, `WAITING_FOR_REVIEW` |
| Listing metadata | ✅ complete |
| Privacy / support / marketing URLs | ✅ set and serving |
| Build in review | ✅ **25**, from Xcode Cloud `Release` on Xcode 26.6 GM. (Builds 1 and 19 are superseded — 1 was built with the local Xcode 27 beta, 19 could not request the Wallet permission) |
| Screenshot sets | ✅ **2**, 5 images each, all `COMPLETE` |
| Privacy nutrition labels | ✅ done by Andrew in the web UI (no API exists) |
| Throwaway review server | ➖ **not provided, by decision** — see below |
| Device verification | ✅ **confirmed on hardware 2026-08-07** — permission prompt and app both work. Itemised sync checks not individually verified. |
| Submission record | ✅ `f3daf509-…`, `WAITING_FOR_REVIEW` |

## Submitted 2026-08-06, resubmitted 2026-08-07

Current submission `f3daf509-6a74-4f57-8ffe-d93c2328b545`, carrying build 25.
It replaced `de454c50-…` (build 19), which was cancelled once that build turned
out to be unable to request the Wallet permission at all.

The original was submitted deliberately ahead of the device test, on Andrew's
call: queue position is worth more than certainty, and a rejection can be
answered with a new build. That trade did not pay off — the bug reached review,
was caught by Andrew rather than by a test, and replacing the build cost the
queue position anyway. The device test that would have caught it was run the
following day, and passed.

Three things were set during the first submission that had never been set
before, and each is an assertion in Andrew's name worth knowing about:

- **Price: Free**, base territory USA, all territories.
- **Age rating: every question answered "no."** No violence, gambling, contests,
  weapons, medical or health topics, messaging, user-generated content,
  unrestricted web access, social media, advertising, or loot boxes. Accurate
  for an app with no content of any kind.
- **Review contact:** set in App Store Connect. Not recorded here — this repo is
  public, and the phone number on that form isn't.

### ⚠️ Risk: App Review cannot exercise the sync

By decision, no test server is provided — that is the product (users bring their
own), and the notes say so plainly. But it means a reviewer cannot see the app's
one feature work.

Compounding it: `ServerConfig.validate` **requires https**, so a reviewer who
clones the open-source server and runs it locally on `http://127.0.0.1:8501`
cannot even enter that address. There is no path to a successful sync on a
reviewer's device without them standing up TLS.

The notes therefore describe what *can* be verified without a server — onboarding,
the connection test failing correctly, the permission prompt and its denial path,
and that zero transactions on a device with no Apple Card history is correct
behaviour rather than an error.

**If this comes back as a 2.1 rejection, that is why**, and the fix is a reachable
https endpoint with synthetic data (scoped in [`app-store.md`](./app-store.md) §4),
not a code change.

## ✅ The device test — passed 2026-08-07

Andrew ran build 25 on a real iPhone and confirmed it works. This was the
project's longest-standing gap: until this point nothing had ever run on
hardware, and the whole premise — that the app can read real transactions — was
unverified. A simulator cannot substitute, since `isDataAvailable` returns
`true` there and the first real query traps inside FinanceKit.

It is also what would have caught the build-19 bug in thirty seconds, and
didn't, because it hadn't been run.

**What remains unticked, and why:** the eleven itemised checks in
[`workstream-app.md`](./workstream-app.md) — pagination past 1000 rows,
batching, corrections re-queueing, balances, background refresh — were not
individually confirmed. "It works" covers the permission prompt and a
functioning app; it does not by itself prove a multi-thousand-row backfill
resumes correctly. Script in [`device-test.md`](./device-test.md).

### Also still open

- **Server exposure.** Deployed but tailnet-only. Funnel is per-port and `:8443`
  also serves an unrelated `/api` route — see `server/deploy.sh`. Now also
  blocking the review server, above.
- **Names don't match, in two places.** The App Store name is **FinanceKit
  Sync**, but the landing page copy still says "FinanceKitSync" — and so does
  the app itself: there is no `CFBundleDisplayName`, so the Home Screen icon and
  the `HomeView` navigation title both read "FinanceKitSync". Visible in
  screenshots 3–5. Not a rejection risk on its own, and a product call rather
  than a bug, but it looks unfinished next to the listing.
- **Homebrew rsync breaks Xcode's export.** `/opt/homebrew/bin/rsync` (3.4.4)
  shadows `/usr/bin/rsync` in `PATH`, and Xcode's IPA packaging step calls
  `rsync -E`, which the Homebrew build rejects on the remote side
  (`--extended-attributes: unknown option`). `xcodebuild -exportArchive` fails
  with a bare "Copy failed". Run exports with
  `env PATH=/usr/bin:/bin:/usr/sbin:/sbin`. This affects Xcode Organizer
  distribution too, not just scripted exports.
- **Tailnet hostname is in git history** (4 commits) and the repo is public.
  Assessed as low risk — a `ts.net` name needs tailnet membership to reach, and
  Funnel is off for that port. Revisit if Funnel is ever enabled on `:8443`.

---

## Workstreams

| # | Workstream | Owner | State | Blocked on |
|---|---|---|---|---|
| A | [iOS app](./workstream-app.md) | Claude | 🟡 signs with the real entitlement, 44 tests pass; **still unproven on device** | Device test |
| B | [Server on `box`](./workstream-server.md) | Claude | 🟢 deployed, 13/13 protocol checks | — (exposure decision open) |
| C | [Landing / privacy / support](./workstream-landing.md) | Claude | 🟢 live on GitHub Pages | — (copy says old name) |
| D | [Xcode Cloud](./xcode-cloud.md) / [releasing](./releasing.md) | Claude | 🟡 connected since 2026-08-04; `Default`, `Release`, `Release Branch`, all on Xcode 26.6 GM | `Release Branch` env vars (manual, UI-only) |
| E | [App Store](./app-store.md) / [listing](./listing.md) | Andrew | 🟢 build 25 `WAITING_FOR_REVIEW` since 2026-08-07 | Apple |

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
| **Individual account disqualifies the request** | Resolved | Did not materialize. Approved on `A29347X2JZ`, an Individual account, 2026-08-06 |
| Entitlement denied or slow | Resolved | Approved and provisioned 2026-08-06. Note for next time: approval and provisioning are two separate steps, and the second one is manual |
| **The app has never read a real transaction** | Resolved 2026-08-07 | Confirmed working on hardware. It stayed open long enough to let a broken build reach App Review — the cost of deferring it was not hypothetical |
| "FinanceKit" in the display name rejected | Low | Rename the listing; bundle ID, repo, and build all unaffected. Fixable same-day, no new binary |
| Funnel port 8443 reclaimed, or its `/api` route exposed | Low–Medium | Funnel is per-port, not per-path. `deploy.sh` keeps it opt-in behind `FKS_ENABLE_FUNNEL=1` |
| Tailnet hostname in public git history | Low | Requires tailnet membership to reach; Funnel off for that port. Revisit if Funnel is enabled on `:8443` |
| Reused/mismatched privacy policy | Resolved | Written fresh and verified against actual app behaviour, including the activity log's account names |
| `gh` token lacks `workflow` scope | Resolved | Pages deploys from a branch, no Actions workflow needed |
| v0 `server/main.py` source lost | Resolved | Contract recovered from `.pyc` and archived in `docs/archive/`; v1 is a rewrite |

## Entitlement — approved, for the record

| | |
|---|---|
| Request ID | `453VPT726K`, filed 2026-08-04, **approved 2026-08-06** |
| Bundle ID | `com.asb.FinanceKitSync` |
| Team | `A29347X2JZ` — an **Individual** account |
| Version sent | **B** — the app as it stands, with no financial-management features |

Two risks were rated high while this was pending, and **neither materialized**:

- **Account type.** Apple's FinanceKit API documentation says the entitlement
  requires an organization-level account, and this file once called that "where
  essentially all the remaining risk sits". It was approved on an Individual
  account regardless. The requirement is not enforced at request time.
- **Financial management tools.** Apple's published criteria ask for net worth,
  spending trends, or budgeting; this app deliberately has none. Approved
  anyway — consistent with LunchSync
  (<https://apps.apple.com/us/app/lunch-sync/id6739702427>), a pure sync tool
  that holds the same entitlement.

The plan to build an Accounts + Trends surface *in order to qualify* is
withdrawn — those screens are worth building on product merit or not at all.
The draft request text is archived in
[`archive/entitlement-request-text.md`](./archive/entitlement-request-text.md);
the Individual → Organization conversion research it prompted is dropped, since
no conversion is needed.

**The lesson worth keeping:** approval and provisioning are two separate steps.
Being granted the entitlement does not enable the capability on the App ID, and
automatic signing will keep minting profiles without it, failing with the same
error indefinitely. See the top of this file.

## Waiting on Andrew

1. **Prove the `Release Branch` path end to end.** All four environment
   variables are set as of 2026-08-07, but no `release/*` push has ever run, so
   the auto-submit has never executed once. It fails soft, so a silent no-op is
   the likely failure mode. **Wait until build 25 clears review** — the first
   run passes `--replace-queued`, which cancels whatever is queued.
   See [`releasing.md`](./releasing.md).
2. **Wait on App Review**, and decide whether to work through the remaining
   itemised device checks in [`device-test.md`](./device-test.md) — the bulk
   sync paths that "it works" does not by itself cover.

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
- **2026-08-06** — **Unparked. Entitlement provisioned.** Apple's approval alone
  did nothing: FinanceKit is a restricted capability, and automatic signing kept
  minting profiles from an App ID that still didn't have it — the same error, on
  a profile regenerated minutes earlier. Enabling it under the App ID's
  *Additional Capabilities* and deleting the cached profile fixed it in one pass.
  A Release device build now signs, and the binary carries
  `com.apple.developer.financekit = [financial-data]`.
- **2026-08-06** — **Build 1.0 (1) on App Store Connect**, `VALID` and attached
  to version 1.0. Two things had to be sorted out first. A plain `archive` is
  signed for *development* (`get-task-allow` true) and ASC rejects it, so the
  archive is now exported through `tools/ExportOptions.plist` with
  `method: app-store-connect`; that step created the team's first Apple
  Distribution certificate, via API-key automatic signing. And the export failed
  with a bare "Copy failed" until `PATH` was cleaned — Homebrew's rsync 3.4.4
  shadows `/usr/bin/rsync` and rejects the `-E` that Xcode's packaging step uses.
- **2026-08-06** — **Screenshots done**, 5 scenes × 6.9"/6.5", uploaded and all
  10 `COMPLETE`. Generated by `tools/screenshots.sh` from a new `#if DEBUG`
  `ScreenshotMode`, which seeds invented state at launch — no FinanceKit query
  ever runs, so no real transaction can reach an image, and the mode is absent
  from the Release binary (verified). Three things this cost that are worth
  remembering: an *unsigned* simulator build can't reach the Keychain, so
  `setToken` failed silently and every scene fell back to onboarding; a fixed
  `sleep` after `simctl launch` races SwiftUI's first frame and produced blank
  white screenshots on 4 of 10 shots; and the obvious fix for that — waiting for
  two byte-identical frames — deadlocks on the one scene with a spinner. The
  capture now waits for two consecutive frames carrying content, and *fails the
  run* rather than shipping a blank.
- **2026-08-06** — **Retracted, same day: "Xcode Cloud was never connected."**
  That claim was entered in this log and in `xcode-cloud.md` on the evidence
  that `/v1/ciProducts` listed only *Dock Me* and *involved*, that the
  `manifest.json` product ID 404'd, and that `apps/6797988167/ciProduct` was
  empty. Those were the API's actual responses, and the conclusion drawn from
  them was still wrong: the product `937ce9c4-…` had existed since 2026-08-04
  with 17 build runs behind it. Why it wasn't listed is unresolved. What holds
  is the narrower point — `FKS_UNENTITLED` is set nowhere, now confirmed
  against this app's own workflows (`Default` and `Release`, both
  `environmentVariables: None`) rather than inferred from a product that
  appeared not to exist.
- **2026-08-06** — **The App Store build has to come from Xcode Cloud, not this
  machine.** The only Xcode installed locally is 27.0 beta 4 (`27A5228h`) with
  the iOS 27 beta SDK, and Apple rejects submissions built with beta tooling —
  so build 1.0 (1), uploaded earlier today, can sit in TestFlight but cannot be
  submitted. Xcode Cloud's `Latest Release` is `17F113` (Xcode 26.6, GM), and
  both workflows are pinned to it. Deployment target is iOS 18.0, so nothing
  here needs the 27 SDK. Andrew declined installing a GM Xcode locally, which
  is also the better call — it keeps the shipping binary coming from one
  reproducible place instead of a laptop.
- **2026-08-06** — Corrected a claim in the "Notes for Review" draft that the
  app *"presents balances, net worth, and spending trends on device."* It does
  not; those screens were never built. The sentence dated from the withdrawn
  plan to add a financial-management surface, and telling App Review the app
  does something it visibly doesn't is a rejection waiting to happen.
- **2026-08-06** — The Individual-account risk, rated **High** in this file and
  called "where essentially all the remaining risk sits", did not materialize.
  Apple approved the entitlement on `A29347X2JZ`, an Individual account. The
  organization requirement in the FinanceKit API docs is not enforced at request
  time. No conversion needed.
- **2026-08-06** — **Submitted for review.** Version 1.0, build 19, from Xcode
  Cloud on Xcode 26.6 GM. Submission `de454c50-…`, `WAITING_FOR_REVIEW` at
  15:14 UTC. Five things had never been set and blocked it, none of them
  mentioned anywhere in this repo's checklists: **app pricing** (nothing had
  ever been set — the submission is rejected outright without it, now Free), the
  **age rating declaration** (every attribute required, all answered "no"), the
  **review contact**, the **review notes**, and attaching the build. Two API
  notes for next time: `ageRatingDeclarations` hangs off `appInfos`, not
  `appStoreVersions`, and is `UPDATE`-only — a `GET` returns 403 and the
  submission error reports its ID as the *version* ID, which is wrong and sends
  you to a 404. Inline creation in `appPriceSchedules` needs the literal
  `${local-id}` format.
- **2026-08-06** — Submitted **before** the device test, on Andrew's call, with
  no review server. Both risks are recorded above rather than smoothed over. The
  app has still never read a real transaction.
- **2026-08-06** — v1.1 subscription planned: 3-day free trial, then $2.99/month.
  See [`subscription.md`](./subscription.md). Two decisions gate the work, and
  one of them expires: **grandfathering v1.0 users cannot be added
  retroactively**, because the signal it depends on
  (`AppTransaction.originalAppVersion`) has to be read on the first launch of
  the paywalled build.
- **2026-08-07** — **The Wallet permission never worked.** Andrew noticed the
  app was absent from Settings › Privacy & Security › Financial Data, which is
  only possible if it never asked. `Info.plist` had
  `NSFinancialDataDescription`; iOS reads `NSFinancialDataUsageDescription`. Two
  things let a one-word typo reach App Review: nothing had ever run on a device,
  and onboarding discarded the authorization result with `try?`, so "never
  granted" and "granted" looked identical from inside the app. Both fixed.
- **2026-08-07** — **Resubmitted as build 25.** `Release` triggered via
  `POST /v1/ciBuildRuns` (~5 minutes to archive), then
  `tools/submit_for_review.py` cancelled `de454c50-…` and submitted
  `f3daf509-…`. A queued submission cannot have its build swapped, so replacing
  one always costs its place in the queue. Also measured: cancellation is
  asynchronous, and attaching a build before the version leaves
  `WAITING_FOR_REVIEW` fails `409 INVALID_STATE`.
- **2026-08-07** — **`Release Branch` workflow created** — push to `release/*`
  archives, uploads, and submits for review. Xcode Cloud cannot submit for
  review itself; `ci_post_xcodebuild.sh` calls the same script used above.
  Environment variables **cannot** be set through the API
  (`environmentVariables` is not a writable attribute on `ciWorkflows`), so the
  workflow ships inert until four variables are added by hand. Everything about
  releasing now lives in [`releasing.md`](./releasing.md).
- **2026-08-07** — Three of those four variables set through the App Store
  Connect UI, and `ASC_KEY` shortly after — all four now set. Also removed a
  bogus start condition from `Release Branch`: it was created matching both the
  `release/` prefix **and** a literal branch named `release`, which does not
  exist, and Apple flagged the workflow with a validation error until it was
  dropped. An API create can produce a workflow the UI considers invalid.
  Two UI traps cost a round trip and are worth remembering: **Add** only stages
  an environment variable while the workflow's **Save** commits it, and ticking
  *Keep value redacted* turns the field into a password input that Chrome
  autofills a saved password into.
- **2026-08-07** — **It works on a real iPhone.** Andrew ran build 25 on
  hardware and confirmed it: the permission prompt appears and the app
  functions. First time anything in this project has run on a device, closing
  the gap that had been the top risk in this file since 2026-08-04 — and that
  let a build which could not request the Wallet permission reach App Review.
  The itemised bulk-sync checks (pagination, batching, corrections, background
  refresh) remain individually unverified.
