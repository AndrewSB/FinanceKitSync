# Workstream B — Sync server on `box`

## Target

| | |
|---|---|
| Host | `box` (Ubuntu 24.04, root, Docker installed) |
| Tailnet name | `$FKS_HOST` — see [Host names](#host-names) |
| Tailnet URL | `https://$FKS_HOST:8501` (Tailscale Serve, tailnet-only) |
| Local bind | `127.0.0.1:8501` |
| Deploy path | `/opt/financekitsync` |
| Data path | `/opt/financekitsync/data/financekitsync.db` |

`box` is behind NAT, nothing inbound but sshd. Funnel is the only practical path
to public HTTPS, and it is already enabled on this tailnet (funnel-capable
ports: **443, 8443, 10000**; 443 and 10000 are taken by existing services).

This service was originally put on **8443** for that reason, and that was a
mistake: 8443 already hosted the box-api router at `/api` and the web UI at
`/`, and `tailscale serve --https=8443 <target>` sets the port's ROOT path — so
every deploy of this service silently evicted the web UI. It now serves on
**8501**, a port it owns outright, where a deploy cannot displace a neighbour
and a future Funnel decision cannot publish someone else's routes.

The cost is that 8501 is not in the Funnel-eligible set, so public (off-tailnet)
reachability is no longer a flag flip. It was never enabled anyway — the phone
syncs over the tailnet. If off-tailnet sync is wanted later, either free one of
443/8443/10000 for this service alone, or accept that funnelling 8443 publishes
box-api and the web UI along with it.

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

> Andrew noted there is already a public reachable API endpoint on `box`, and
> that folding this in as an additional route there is preferable long-term. v1
> stands up its own Funnel port to keep the streams independent; consolidating
> onto the existing endpoint is a follow-up, not a blocker.

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
4. `tailscale serve --bg --https 8501 http://127.0.0.1:8501`
5. Verify from another tailnet node: `curl "https://$FKS_HOST:8501/health"`

## Verification checklist

- [ ] `/health` reachable from cellular (off-tailnet)
- [ ] `POST` without token → 401
- [ ] `POST` with token → 200, rows land in SQLite
- [ ] Replaying the identical packet → `transactions_inserted: 0`, no duplicates
- [ ] A changed amount on an existing id → `transactions_updated: 1`
- [ ] Container survives `reboot`
- [ ] DB file is backed up somewhere

## Open items

- [ ] Backup strategy for `financekitsync.db` (nightly `sqlite3 .backup` → offsite)
- [ ] Consolidate onto the existing public endpoint rather than a second Funnel port
- [ ] Log rotation for uvicorn output
