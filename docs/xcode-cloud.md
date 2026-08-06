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

**Not connected.** This section previously said "Connected" on the strength of
Xcode having written
`app/FinanceKitSync.xcodeproj/xcshareddata/xcodecloud/manifest.json`. Checked
against the API on 2026-08-06, that file describes a product App Store Connect
has never heard of:

```
GET /v1/ciProducts            → only "Dock Me" and "involved"
GET /v1/ciProducts/1eeb2fcc-…  → 404 NOT_FOUND
GET /v1/apps/6797988167/ciProduct → empty
```

So the manifest is a local leftover from a setup that didn't complete, not
evidence of a connection. **There are no workflows for this app**, which also
means there is no `FKS_UNENTITLED` anywhere to remove — see below.

The manifest is tracked in git and harmless; Xcode will overwrite it with real
IDs when the setup below is actually finished.

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

Verified 2026-08-06 that it is set nowhere: the only Xcode Cloud products on this
team are *Dock Me* and *involved*, neither of which defines any environment
variables, and FinanceKitSync has no product at all.

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
