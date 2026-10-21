# Workstream B — Sync server on `box`

## Target

| | |
|---|---|
| Host | `box` (Ubuntu 24.04, root, Docker installed) |
| Tailnet name | `$FKS_HOST` — see [Host names](#host-names) |
| App URL | `https://$FKS_HOST:8443/api/financekit` (through Box API) |
| Local bind | `127.0.0.1:8501` |
| Deploy path | `/opt/financekitsync` |
| Data path | `/opt/financekitsync/data/financekitsync.db` |

FinanceKitSync is an RPC service, not a network boundary. Docker publishes it
only on `127.0.0.1:8501`; there is no Tailscale Serve or Funnel listener for
that port. Box API forwards its namespaced routes under `/api/financekit` and
is the only component that decides what crosses the machine boundary.

### Host names

This repo is public, so it never spells out the tailnet name, the tailnet IP, or
the egress IP — a Funnel endpoint is publicly routable by design, and naming it
here turns an unguessable host into a documented target. Docs and scripts use
`$FKS_HOST` (or `box.example.ts.net` where a literal is needed for illustration).

Get the real value locally with `tailscale status --json | jq -r .Self.DNSName`,
and export it before following any command below:

```bash
export FKS_HOST="$(tailscale status --json | jq -r '.Self.DNSName | sub("\\.$";"")')"
```

## Stack

Python 3.12 · FastAPI · uvicorn · SQLite (WAL) · Docker · systemd unit for
restart-on-boot.

SQLite rather than the Postgres already on the box: this is a single-writer,
append-mostly workload with no other consumer, and a file-backed DB makes
"back up your financial data" a `cp`. If a consumer ever needs joins against
other data, migrating is a `.dump` away.

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | none | Liveness. The app's "Test connection" hits this. |
| POST | `/financekit-sync` | Bearer | Accept a packet. Idempotent upsert. |
| GET | `/accounts` | Bearer | Current balances. Convenience for downstream tooling. |
| GET | `/transactions?since=&limit=` | Bearer | Paged read-back. |

`/health` is deliberately unauthenticated so onboarding can verify reachability
before a token is entered. It returns only `{"status":"ok","schema_version":1}`
— no counts, no hostname, nothing that helps an unauthenticated scanner.

## Auth

Single bearer token, supplied via the `FKS_TOKEN` environment variable, compared
with `hmac.compare_digest`. One token, one user — this is a personal server, and
a token table would be complexity without a second principal to justify it.

Rotation: change `FKS_TOKEN`, restart, update the token in the app.

## Deployment steps

1. `rsync` `server/` to `/opt/financekitsync`
2. Write `/opt/financekitsync/.env` with `FKS_TOKEN` (mode `0600`)
3. `docker compose up -d --build`
4. Verify locally: `curl http://127.0.0.1:8501/health`
5. Verify through Box API: `curl "https://$FKS_HOST:8443/api/financekit/health"`

## Verification checklist

- [ ] `/financekit/health` reachable through Box API from a tailnet device
- [ ] `POST` without token → 401
- [ ] `POST` with token → 200, rows land in SQLite
- [ ] Replaying the identical packet → `transactions_inserted: 0`, no duplicates
- [ ] A changed amount on an existing id → `transactions_updated: 1`
- [ ] Container survives `reboot`
- [ ] DB file is backed up somewhere

## Open items

- [ ] Backup strategy for `financekitsync.db` (nightly `sqlite3 .backup` → offsite)
- [ ] Log rotation for uvicorn output
