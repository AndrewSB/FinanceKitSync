# Xcode Cloud setup

Xcode Cloud workflows live in App Store Connect, not in this repository — there
is no file format for them. Everything that *can* live in the repo does: the
build scripts in [`../ci_scripts/`](../ci_scripts/).

**For day-to-day releasing, read [`releasing.md`](./releasing.md) instead.**
This file is the account-level setup: how the connection was made, what each
workflow contains, and what cannot be automated.

## What is and isn't scriptable

The initial GitHub grant is **interactive OAuth** — it installs the Xcode Cloud
GitHub App and there is no CLI or API for it. That was done on 2026-08-04 and
does not need repeating.

Everything after it *mostly* is scriptable. Workflows can be created, read, and
edited through `POST /v1/ciWorkflows`, and builds started with
`POST /v1/ciBuildRuns` — both used in anger on 2026-08-07. **The exception is
environment variables:** `environmentVariables` is not a writable attribute on
`ciWorkflows`, so any workflow needing an environment must have it entered by
hand. That is the one manual step left in the release path.

Xcode Cloud finds `ci_scripts/` at the repository root automatically; no
configuration needed. The scripts must stay executable — if that's ever lost,
`git update-index --chmod=+x ci_scripts/*.sh`. Note it requires a **shared**
scheme; it cannot see per-user ones.

## Connection status

**Connected**, and has been since 2026-08-04.

| | |
|---|---|
| Product ID | `937ce9c4-6e56-43d2-aaf1-b3edaa9e8195`, created 2026-08-04 |
| Repository | `AndrewSB/FinanceKitSync` via the `GITHUB_CLOUD` provider |
| Workflows | `Default` (build on `main`), `Release` (manual archive), `Release Branch` (archive + auto-submit on `release/*`, created 2026-08-07). Day-to-day usage lives in [`releasing.md`](./releasing.md). |

> **A wrong entry was here, and it's worth recording why.** On 2026-08-06 this
> section was rewritten to say "Not connected", on the evidence that
> `GET /v1/ciProducts` returned only *Dock Me* and *involved*, that the product
> ID in `manifest.json` 404'd, and that `apps/6797988167/ciProduct` was empty.
> All three were real responses. But the product had existed since 2026-08-04
> the whole time, with 17 build runs behind it — it simply wasn't listed. The
> `manifest.json` ID (`1eeb2fcc-…`) is stale, but the *target* ID in that same
> file matches the live product, so the file was never the fabrication it was
> accused of being.
>
> Why the API omitted it is unresolved. The lesson is narrower than "the API
> lies": an empty collection response is weaker evidence than a positive one,
> and "X does not exist" deserves a second, differently-shaped query before it
> gets written down as fact.

## Workflows

Three exist. Edit them in **App Store Connect → Xcode Cloud → Manage Workflows**,
or through `POST`/`PATCH /v1/ciWorkflows` — except their environment variables,
which are UI-only.

All of them build with the real entitlement. There is no escape hatch on any of
them: the FinanceKit capability was enabled on the App ID on 2026-08-06, so
Archive actions sign cleanly.

### 1. `Default` — build on `main`

| Setting | Value |
|---|---|
| id | `7F0BF1FC-59D6-4D36-844A-76F3A5A07365` |
| Start Condition | **Branch Changes** → `main` |
| Actions | **Build** (scheme `FinanceKitSync`, `ANY_IOS_DEVICE`) |

Xcode created this one during first-run setup; it was never designed. No signing
and no upload, so it is a fast "main is not broken" check and nothing more. It
is also redundant with the `PR Check` workflow described below, which is
probably the better version of the same idea.

### 2. `Release` — manual, produces the build you submit

| Setting | Value |
|---|---|
| id | `D5C50052-983C-4907-80C5-72603704C78A` |
| Start Condition | **Manual** |
| Environment | "Latest Release" — 17F113 / Xcode 26.6 GM |
| Actions | **Archive**, scheme `FinanceKitSync`, `APP_STORE_ELIGIBLE` |

Start it from Xcode's Report navigator, from App Store Connect, or with
`POST /v1/ciBuildRuns` — see [`releasing.md`](./releasing.md). Builds 19 and 25
both came from here. It uploads but does not submit.

### 3. `Release Branch` — push to `release/*`, land in review

**Created 2026-08-07**, id `90599769-efd9-4097-8ccd-1bedd07ff14e`, via
`POST /v1/ciWorkflows`.

| Setting | Value |
|---|---|
| Start Condition | **Branch Changes** → `release/` (prefix) |
| Environment | "Latest Release" — 17F113 / Xcode 26.6 GM, macOS 25G72. **Not** the 27 beta; Apple rejects beta-built submissions. |
| Actions | **Archive**, scheme `FinanceKitSync`, `APP_STORE_ELIGIBLE` |
| Environment Variables | all four set 2026-08-07 |

This is the hands-off path: push to a `release/*` branch and the build reaches
App Store review with no clicks. The archive is Xcode Cloud's part;
`ci_scripts/ci_post_xcodebuild.sh` does the rest by calling
[`tools/submit_for_review.py`](../tools/submit_for_review.py).

> **All four are set as of 2026-08-07 — but the path has never run.**
> Environment variables **cannot be set through the App Store Connect API** —
> `environmentVariables` is not a writable attribute on `ciWorkflows`, and the
> request is rejected as an unknown attribute. They have to be entered in
> **App Store Connect → Xcode Cloud → Manage Workflows → Release Branch →
> Environment**.
>
> | Key | Value | Secret | |
> |---|---|---|---|
> | `FKS_AUTO_SUBMIT` | `1` | no | ✅ |
> | `ASC_KEY_ID` | the key ID | no | ✅ |
> | `ASC_ISSUER_ID` | the issuer ID | no | ✅ |
> | `ASC_KEY` | the **contents** of the `.p8` file | **yes** | ✅ |
>
> ⚠️ **Two traps when entering these, both hit for real on 2026-08-07.**
> First, **Add only stages the variable — the workflow's Save button commits
> it.** A variable added and not saved vanishes silently, and the list looks
> identical until you reload. Second, ticking *Keep value redacted* turns Value
> into a password field, and **Chrome will autofill a saved password into it**.
> Type the name and paste the value first, tick Secret last, and check the field
> still holds what you pasted. A redacted value cannot be read back, so a wrong
> one is invisible until a build fails.
>
> Get the key onto the clipboard without opening it:
> `pbcopy < ~/path/to/AuthKey_XXXXXXXXXX.p8`. Paste the whole file including the
> BEGIN/END lines — `ci_post_xcodebuild.sh` writes it back out verbatim, and a
> partial paste fails at JWT signing with an unhelpful error.
>
> Until it exists the workflow archives and uploads but skips submission,
> logging why. That is inert, not broken — but a release you assumed was
> submitted will be sitting in App Store Connect untouched.

### Never created: `PR Check` and `Main`

Earlier revisions of this file specified two more workflows — a `PR Check`
(build + test on pull requests targeting `main`) and a `Main` (archive to
TestFlight on every merge). Neither was ever created, and the repo has run
without them the whole time.

`PR Check` is still worth adding if pull requests start being used; `Main` is
not, now that `Release Branch` covers releasing and TestFlight-on-every-merge
would burn build minutes for no one.

## Why submission needs a script at all

**Xcode Cloud cannot submit for review.** Its Archive action tops out at
uploading a build and optionally distributing to TestFlight; creating the review
submission is App Store Connect API only (`POST /v1/reviewSubmissions`, an item
pointing at the version, then `PATCH … submitted: true`). Nothing in the
workflow UI does this, which is why the last mile lives in the repo.

Three things about that script are worth knowing before you rely on it:

- **It forfeits queue position when it replaces a submission.** A submission in
  `WAITING_FOR_REVIEW` cannot have its build swapped — Apple freezes it. So
  "push a fix and it replaces the queued build" really means *cancel the old
  submission, create a new one*, and go to the back of the line. Run by hand,
  the script refuses to do this without `--replace-queued`; from CI that flag is
  always passed, because otherwise a release push would silently do nothing.
- **It waits, because an uploaded build is not immediately usable.** Processing
  takes minutes to well over half an hour, and the script polls for up to 45
  minutes. That wait happens *inside* the Xcode Cloud run, so a release build
  occupies a compute slot far longer than a normal archive.
- **It fails soft.** A failed submission never fails the build — the archive is
  already uploaded and good. Re-run `tools/submit_for_review.py --build N`
  locally to finish the job.

- **Its build numbers come from a fresh counter.** `ci_pre_xcodebuild.sh` sets
  the build number from `$CI_BUILD_NUMBER`, which Xcode Cloud increments *per
  workflow*. Build 19 came from `Release`'s counter, so a new workflow starts
  its own — and App Store Connect rejects a duplicate build number within a
  version. Expect one collision on the first `Release Branch` archive, fixed by
  bumping that workflow's build number once in App Store Connect.

Every guard is opt-in and layered: not an archive action, `FKS_AUTO_SUBMIT`
unset, not a `release/*` branch, or credentials missing — any one of those and
the script does nothing but say so.

## Scripting these instead

Already done. Workflows are created and edited through
`POST`/`PATCH /v1/ciWorkflows` and builds started with `POST /v1/ciBuildRuns`,
using the Admin-role App Store Connect API key described in
[`releasing.md`](./releasing.md). `Release Branch` was created that way on
2026-08-07 rather than clicked.

The one thing that still cannot be scripted is a workflow's environment
variables — see above.

## The `FKS_UNENTITLED` escape hatch — retired

Setting `FKS_UNENTITLED=1` made `ci_post_clone.sh` swap in
`app/Supporting/FinanceKitSync-Unentitled.entitlements`, so the pipeline could be
built and validated while signing was impossible. Those builds installed and ran
but read no financial data.

**No longer needed, and it must not be set on any workflow.** The entitlement was
approved and provisioned on 2026-08-06.

**This cannot be verified through the API**, and a claim here that it had been
is withdrawn. That check read `environmentVariables: None` off a workflow and
took it as "no variables set" — but the field does not exist on `ciWorkflows` at
all, so `None` meant *absent*, not *empty*. Confirmed 2026-08-07 when a create
call rejected the same attribute as unknown. To actually check, look at each
workflow's Environment in App Store Connect.

The mechanism stays in `ci_post_clone.sh` — it costs nothing, and it is the
fastest way back to a green pipeline if the entitlement is ever revoked or a
future bundle ID has to be re-approved. But a build produced with it is data-blind
and must never be shipped.

## Verifying locally

The commands live in [`releasing.md`](./releasing.md) § *Verifying before you
release*, alongside the pitfall that costs the most time (passing
`CODE_SIGNING_ALLOWED=NO` to a **test** run breaks Keychain writes and produces
a failure that looks like a code bug).

Both the simulator build and the signed Release device build were confirmed
passing on 2026-08-07.
