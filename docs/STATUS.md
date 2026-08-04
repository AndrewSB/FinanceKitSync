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
| D | [Xcode Cloud](./xcode-cloud.md) / [App Store](./app-store.md) | Andrew | 🔴 **critical path** | Andrew: file the FinanceKit request |

Workstreams A and B are independent and run in parallel. C depends on both. D's
long pole (the entitlement) is independent of everything and should start now.

## Critical path

```
FinanceKit entitlement request ──────────────────────► approval ──► App Review
        (file today, days-to-weeks, out of our hands)
A: iOS app ──┐
             ├──► end-to-end verified ──► C: landing page
B: server ───┘
```

Nothing in A, B, or C is blocked by the entitlement. A development build runs on
a registered device under a personal team without it — only **distribution**
requires approval. Do not let the wait idle the other streams.

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

## Waiting on Andrew

Three decisions block progress. Nothing else does.

1. **File the FinanceKit entitlement request.** The longest pole by far, and
   entirely external. Text is drafted in [`app-store.md`](./app-store.md) §0.
2. **Decide how the server gets exposed publicly.** It's deployed and working
   but tailnet-only — see the Funnel note below.
3. **Decide whether the repo goes public.** GitHub Pages is unavailable on a
   private repo on the free plan (confirmed: HTTP 422, "Your current plan does
   not support GitHub Pages for this repository"). The `gh-pages` branch is
   already pushed and will serve the moment either changes.

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
- **2026-08-04** — **Funnel incident.** Enabling Funnel on `:8443` also
  published a pre-existing `/api → 127.0.0.1:8444` route that had been
  tailnet-only, because Funnel is per-port, not per-path. Worse, `tailscale
  funnel --https=8443 off` deleted the port's *entire* serve config, taking
  that neighbouring route with it. Both were restored and the original public
  posture (Funnel on `:10000` and `:3000` only) verified via `tailscale funnel
  status`. Funnel is now opt-in in `deploy.sh` behind `FKS_ENABLE_FUNNEL=1`.
  Note also that curling a `ts.net` name from a machine on the tailnet proves
  nothing about public reachability — only `tailscale funnel status` does.
