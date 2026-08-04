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

**Connected.** Xcode wrote
`app/FinanceKitSync.xcodeproj/xcshareddata/xcodecloud/manifest.json`:

| | |
|---|---|
| Product ID | `1eeb2fcc-69bc-4b1a-9296-7095ddc94e93` |
| Target ID | `937ce9c4-6e56-43d2-aaf1-b3edaa9e8195` (`FinanceKitSync`) |

That file is tracked in git — it's shared, not per-user.

## ⚠️ Archiving is blocked until the entitlement lands

Worth being clear before you build any of these: **any workflow with an Archive
action will fail at signing** until Apple approves the FinanceKit entitlement.
Not "produces a broken build" — the build errors out:

```
Provisioning profile "..." doesn't include the FinanceKit capability.
Entitlement com.apple.developer.financekit requires approval from Apple.
```

So today, only workflow 1 (Build + Test, no signing) will go green. Workflows 2
and 3 are worth creating now so they're ready, but expect them to fail until
approval — or set `FKS_UNENTITLED = 1` on workflow 2 to get an installable (but
data-blind) TestFlight build for UI testing.

**For today's device test, don't wait on Xcode Cloud.** Build straight to the
iPhone from Xcode with the unentitled variant — it's one step instead of a
cloud round trip, and it's the same resulting app.

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
| Environment Variables | `FKS_UNENTITLED` = `1` *(temporary — see above; delete after approval)* |

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

## The `FKS_UNENTITLED` escape hatch

Signing fails today, because the FinanceKit entitlement isn't approved yet:

```
error: Entitlement com.apple.developer.financekit requires approval from Apple
to include in a profile.
```

Setting `FKS_UNENTITLED=1` makes `ci_post_clone.sh` swap in
`app/Supporting/FinanceKitSync-Unentitled.entitlements`, so the pipeline can be
built and validated in the meantime. Those builds install and run but read no
financial data.

**Remove `FKS_UNENTITLED` from workflows 1 and 2 the day the entitlement is
approved,** and never set it on `Release`. See [`app-store.md`](./app-store.md).

## Verifying locally

The same builds Xcode Cloud runs, reproduced on your machine:

```bash
cd app

# What "PR Check" does
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# What "Main" does today, pre-approval
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -sdk iphoneos -destination 'generic/platform=iOS' -configuration Release \
  -allowProvisioningUpdates \
  CODE_SIGN_ENTITLEMENTS=Supporting/FinanceKitSync-Unentitled.entitlements build
```

Both are confirmed passing as of 2026-08-04.
