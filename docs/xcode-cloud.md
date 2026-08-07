# Xcode Cloud setup

Xcode Cloud workflows live in App Store Connect, not in this repository — there
is no file format for them and no API to create them, so the definitions below
have to be entered once through the UI. Everything that *can* live in the repo
does: the build scripts in [`../ci_scripts/`](../ci_scripts/).

## What I can and can't do

Xcode Cloud's first-run setup is **interactive OAuth** — granting Apple access
to your GitHub account installs the Xcode Cloud GitHub App, and there is no CLI
or API for that step. Everything downstream (workflows, build scripts) is
scriptable via the App Store Connect API, but the grant is not.

So the split is:

| | |
|---|---|
| **Done, in the repo** | `ci_scripts/ci_post_clone.sh`, `ci_scripts/ci_pre_xcodebuild.sh`, the shared scheme (Xcode Cloud requires a *shared* scheme — it can't see per-user ones), the workflow definitions below |
| **Needs you, ~10 minutes** | The GitHub grant, then clicking through the three workflows |

## Prerequisites

- **Paid Apple Developer Program membership.** Xcode Cloud is included, but the
  account must be active. See the eligibility warning in
  [`app-store.md`](./app-store.md) §0 — this may need resolving first.
- **The repo must be reachable by Apple.** It is currently **private**;
  Xcode Cloud can build private repos, but the grant has to cover it.

## One-time setup

1. Open `app/FinanceKitSync.xcodeproj` in Xcode.
2. **Product › Xcode Cloud › Create Workflow.**
3. Select the `FinanceKitSync` app target. Xcode detects the shared scheme.
4. When prompted, **grant access to `AndrewSB/FinanceKitSync`**. This installs
   the Xcode Cloud GitHub App and is what makes branch and PR triggers work.
   *(This is the step I can't do for you.)*
5. Xcode offers a default "Build" workflow — accept it, then edit it and add the
   other two per the table below.

Xcode Cloud finds `ci_scripts/` at the repository root automatically; no
configuration needed. The scripts must stay executable — if that's ever lost,
`git update-index --chmod=+x ci_scripts/*.sh`.

> **Tell me once the grant is done** and I can take over managing workflows,
> triggers, and build settings through the App Store Connect API from there.

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

## ✅ Archiving is no longer blocked

This section used to warn that any workflow with an Archive action would fail at
signing. **Resolved 2026-08-06** — the FinanceKit capability was enabled on the
App ID, Xcode minted a profile carrying `com.apple.developer.financekit`, and a
local Release device build signs. All three workflows below can be created and
run as written, with no escape hatch on any of them.

## Workflows

Create these in Xcode: **Product › Xcode Cloud › Manage Workflows › +**.

### 1. `PR Check` — the one that works today

| Setting | Value |
|---|---|
| Start Condition | **Pull Request Changes** → target branch `main` |
| Environment | Xcode 27.x, macOS latest, **Clean: off** |
| Actions | **Build** (scheme `FinanceKitSync`, platform iOS) |
| | **Test** (scheme `FinanceKitSync`, destination *iPhone 17 Pro*, iOS 27) |
| Post-Actions | none |
| Environment Variables | none |

No signing, no upload — so this is green regardless of the entitlement. This is
your safety net on every PR.

> Don't add `FKS_UNENTITLED` here. Without an Archive action there's nothing to
> sign, so it would do nothing but confuse.

### 2. `Main` — TestFlight on every merge

| Setting | Value |
|---|---|
| Start Condition | **Branch Changes** → `main` |
| | **Files and Folders**: `app/**` *(so docs/server commits don't burn builds)* |
| Environment | Xcode 27.x, macOS latest |
| Actions | **Archive** (scheme `FinanceKitSync`, **Deployment Preparation: TestFlight (Internal Testing Only)**) |
| Post-Actions | **TestFlight Internal Testing** → your internal group |
| Environment Variables | **none** — the entitlement is approved, so this builds with the real one |

### 3. `Release` — manual, ships to review

| Setting | Value |
|---|---|
| Start Condition | **Manual** |
| Environment | Xcode 27.x, macOS latest |
| Actions | **Archive** (scheme `FinanceKitSync`, **Deployment Preparation: App Store Connect**) |
| Post-Actions | **TestFlight External Testing** → your external group |
| Environment Variables | **none** — this must build with the real entitlement |

Start it from Xcode's Report navigator or from App Store Connect. This is the
workflow that produces the build you submit.

### 4. `Release Branch` — push to `release/*`, land in review

**Created 2026-08-07**, id `90599769-efd9-4097-8ccd-1bedd07ff14e`, via
`POST /v1/ciWorkflows`.

| Setting | Value |
|---|---|
| Start Condition | **Branch Changes** → `release/` (prefix) and `release` |
| Environment | "Latest Release" — 17F113 / Xcode 26.6 GM, macOS 25G72. **Not** the 27 beta; Apple rejects beta-built submissions. |
| Actions | **Archive**, scheme `FinanceKitSync`, `APP_STORE_ELIGIBLE` |
| Environment Variables | ⚠️ **not set — you must add these by hand** |

This is the hands-off path: push to a `release/*` branch and the build reaches
App Store review with no clicks. The archive is Xcode Cloud's part;
`ci_scripts/ci_post_xcodebuild.sh` does the rest by calling
[`tools/submit_for_review.py`](../tools/submit_for_review.py).

> **⚠️ One manual step remains, and the workflow will not submit without it.**
> Environment variables **cannot be set through the App Store Connect API** —
> `environmentVariables` is not a writable attribute on `ciWorkflows`, and the
> request is rejected as an unknown attribute. So the workflow exists and is
> enabled, but arrives with no environment at all.
>
> Add these once in **App Store Connect → Xcode Cloud → Manage Workflows →
> Release Branch → Environment**:
>
> | Key | Value | Secret |
> |---|---|---|
> | `FKS_AUTO_SUBMIT` | `1` | no |
> | `ASC_KEY_ID` | the key ID | no |
> | `ASC_ISSUER_ID` | the issuer ID | no |
> | `ASC_KEY` | the **contents** of the `.p8` file | **yes** |
>
> Until they exist the workflow archives and uploads but skips submission,
> logging why. That is inert, not broken — but a release you assumed was
> submitted will be sitting in App Store Connect untouched.

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

Workflows can be created and edited through the App Store Connect API
(`POST /v1/ciWorkflows`) rather than clicked. That needs an API key:
**App Store Connect → Users and Access → Integrations → App Store Connect API**,
role **Admin** (workflow management needs more than App Manager), then download
the `.p8`.

If you'd rather have these defined as code — reproducible, reviewable, and
re-creatable — put the `.p8` somewhere gitignored, tell me the path, and I'll
write a script that creates all three idempotently. Worth doing if you expect to
tweak them; not worth it if you'll set them once and forget.

## The `FKS_UNENTITLED` escape hatch — retired

Setting `FKS_UNENTITLED=1` made `ci_post_clone.sh` swap in
`app/Supporting/FinanceKitSync-Unentitled.entitlements`, so the pipeline could be
built and validated while signing was impossible. Those builds installed and ran
but read no financial data.

**No longer needed, and it must not be set on any workflow.** The entitlement was
approved and provisioned on 2026-08-06.

Verified 2026-08-06 against this app's own workflows: both `Default` and
`Release` report `environmentVariables: None`.

The mechanism stays in `ci_post_clone.sh` — it costs nothing, and it is the
fastest way back to a green pipeline if the entitlement is ever revoked or a
future bundle ID has to be re-approved. But a build produced with it is data-blind
and must never be shipped.

## Verifying locally

The same builds Xcode Cloud runs, reproduced on your machine:

```bash
cd app

# What "PR Check" does
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# What "Main" and "Release" do — the real entitlement, no override
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -sdk iphoneos -destination 'generic/platform=iOS' -configuration Release \
  -allowProvisioningUpdates build
```

Both are confirmed passing as of 2026-08-06, the second one now signing with the
real FinanceKit entitlement.
