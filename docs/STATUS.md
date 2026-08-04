# Status

Single source of truth for where the project stands. Update the date and the
table whenever something moves.

**Last updated:** 2026-08-04

## Workstreams

| # | Workstream | Owner | State | Blocked on |
|---|---|---|---|---|
| A | [iOS app](./workstream-app.md) | Claude | 🟡 in progress | — |
| B | [Server on `box`](./workstream-server.md) | Claude | 🟡 in progress | — |
| C | [Landing page](./workstream-landing.md) | Claude | ⚪ not started | A + B working end-to-end |
| D | [App Store / Xcode Cloud](./app-store.md) | Andrew | 🔴 **critical path** | FinanceKit entitlement approval |

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

## Log

- **2026-08-04** — Repo created. Spec written. Recovered the v0 wire contract
  from `LunchSync/server/__pycache__/main.cpython-314.pyc` after finding the
  source file gone. Confirmed `box` reachable, Funnel-capable on 443/8443/10000
  with 8443 free. Confirmed local signing identity for team `A29347X2JZ`.
