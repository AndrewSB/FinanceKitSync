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

## Workflows

### 1. `PR Check` — branch automation

| | |
|---|---|
| Start condition | **Pull Request Changes**, target branch `main` |
| Environment | Xcode 27, macOS latest |
| Actions | Build (`iOS`), Analyze |
| Post-action | none |
| Env vars | `FKS_UNENTITLED = 1` *(see below)* |

Catches compile breaks on every PR. No signing, no upload.

### 2. `Main` — branch automation

| | |
|---|---|
| Start condition | **Branch Changes**, `main`, files/paths `app/**` |
| Environment | Xcode 27, macOS latest |
| Actions | Archive (`iOS`) |
| Post-action | **TestFlight (Internal Testing Only)** |
| Env vars | `FKS_UNENTITLED = 1` *(remove after approval)* |

The path filter matters: without it, every docs or server commit burns a build.

### 3. `Release` — manual

| | |
|---|---|
| Start condition | **Manual** |
| Environment | Xcode 27, macOS latest |
| Actions | Archive (`iOS`) |
| Post-action | **TestFlight (External Testing Groups)** |
| Env vars | *(none — must build with the real entitlement)* |

Run from Xcode's Report navigator or App Store Connect when you actually intend
to ship. This is the workflow that feeds App Store submission.

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
