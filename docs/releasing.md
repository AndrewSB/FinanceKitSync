# Releasing

Every way a build can reach the App Store, what each one automates, and what it
cannot. For where the current release actually stands, see
[`STATUS.md`](./STATUS.md); for the Xcode Cloud account setup behind all of
this, [`xcode-cloud.md`](./xcode-cloud.md).

## The three paths

| | Trigger | Produces | Submits for review? |
|---|---|---|---|
| `Default` | push to `main` | a build, nothing else | no |
| `Release` | manual | archive uploaded to App Store Connect | no — you click Submit |
| `Release Branch` | push to `release/*` | archive uploaded | **yes**, automatically |

All three live in App Store Connect, not this repo — see `xcode-cloud.md` for
why, and for their exact settings.

## The normal release

```bash
git switch -c release/1.1 && git push -u origin release/1.1
```

That is the whole thing. `Release Branch` archives, uploads, and
`ci_scripts/ci_post_xcodebuild.sh` submits the build for review once App Store
Connect finishes processing it.

Watch it land:

```bash
python3 tools/asc.py get "/v1/ciProducts/937ce9c4-6e56-43d2-aaf1-b3edaa9e8195/workflows"
```

## Releasing by hand

When you want the archive but not the submission — or the automation is
misbehaving — start `Release` from Xcode's Report navigator, or:

```bash
python3 - <<'EOF'
import sys; sys.path.insert(0, "tools")
import asc
asc.post("/v1/ciBuildRuns", {"data": {"type": "ciBuildRuns", "relationships": {
    "workflow": {"data": {"type": "ciWorkflows", "id": "D5C50052-983C-4907-80C5-72603704C78A"}},
    "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": "7ca6bc3b-232b-47ac-8227-49327ebe22c4"}}}}})
EOF
```

Then submit whenever you're ready — the script is the same one CI runs:

```bash
python3 tools/submit_for_review.py --build 25 --dry-run   # show the plan
python3 tools/submit_for_review.py --build 25             # do it
```

It waits for processing, attaches the build to the editable version, and
creates + submits the review submission. Every step checks state first, so a
run that dies partway can simply be re-run.

## Credentials

Everything here needs an App Store Connect API key with **Admin** role (App
Manager cannot manage workflows):

```bash
export ASC_KEY_ID=...
export ASC_ISSUER_ID=...        # Users and Access -> Integrations, top of page
export ASC_KEY_PATH=~/path/to/AuthKey_XXXXXXXXXX.p8
python3 tools/asc.py whoami     # proves all three
```

Put these in `~/.secrets` (sourced by `~/.zprofile`, gitignored, never in the
repo).

## What is NOT automated, and why

- **Environment variables cannot be set through the API.**
  `environmentVariables` is not a writable attribute on `ciWorkflows` — the
  request is rejected outright. The four variables `Release Branch` needs are
  entered by hand in App Store Connect → Xcode Cloud → Manage Workflows →
  Release Branch → Environment. `FKS_AUTO_SUBMIT=1`, `ASC_KEY_ID` and
  `ASC_ISSUER_ID` were set on 2026-08-07; **`ASC_KEY` (the contents of the
  `.p8`, marked secret) is still missing**, and until it exists the workflow
  archives and uploads but skips submission, saying so in the log — inert, not
  broken.
- **Xcode Cloud cannot submit for review at all.** Its Archive action stops at
  uploading; the review submission is App Store Connect API only. That is the
  entire reason `tools/submit_for_review.py` exists.
- **Version records, pricing, age rating, and review contact** are set in the
  web UI and are not touched by any of this.

## Things that will bite you

- **Build numbers come from a per-workflow counter.** `ci_pre_xcodebuild.sh`
  sets the build number from `$CI_BUILD_NUMBER`, which each workflow increments
  independently. `Release` produced build 25 on its 25th run; `Release Branch`
  starts its own count at 1 and App Store Connect rejects a duplicate build
  number within a version. **Expect the first `Release Branch` archive to
  collide** and need a one-time build-number bump on that workflow.
- **Replacing a queued submission forfeits its place in the review queue.** A
  submission in `WAITING_FOR_REVIEW` cannot have its build swapped — Apple
  freezes it — so `--replace-queued` cancels and re-creates. There is no way
  around this; the queued submission carries the old binary by definition.
- **Cancelling is asynchronous.** MEASURED 2026-08-06: the cancel returns 200
  while the version sits in `WAITING_FOR_REVIEW` for a few more seconds before
  settling into `DEVELOPER_REJECTED`, and attaching a build in that window fails
  `409 INVALID_STATE`. `submit_for_review.py` waits it out; if you are driving
  the API by hand, so should you.
- **Submission failure never fails the build.** `ci_post_xcodebuild.sh` fails
  soft on purpose — a good archive should not be marked red by a bad submission
  — so *check that the submission actually happened*. A release that silently
  did not submit looks exactly like a green build.
- **A beta Xcode poisons the submission.** Apple rejects builds made with a beta
  toolchain. Both archive workflows pin "Latest Release" (currently 17F113 /
  Xcode 26.6 GM). The local Xcode on this machine is 27.0 beta 4, which is why
  local archives are for verification only and never for submission.

## Verifying before you release

The simulator cannot exercise FinanceKit — it reports data as available and
then traps on the first real query (see
[`FinanceKitAvailabilityTests`](../app/FinanceKitSyncTests/FinanceKitAvailabilityTests.swift)).
So a green test run says nothing about whether the app can actually read
transactions. **Run it on a device before releasing** — see
[`device-test.md`](./device-test.md). Build 19 shipped to review unable to
request the Wallet permission at all, and a thirty-second device check would
have caught it.

```bash
cd app

# what Default does
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# tests — note: do NOT pass CODE_SIGNING_ALLOWED=NO here. An unsigned app has
# no keychain access group, so Keychain writes fail and the suite reports a
# confusing ".notConfigured" failure that has nothing to do with your change.
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# what the archive workflows do
xcodebuild -project FinanceKitSync.xcodeproj -scheme FinanceKitSync \
  -sdk iphoneos -destination 'generic/platform=iOS' -configuration Release \
  -allowProvisioningUpdates build
```
