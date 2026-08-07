# FinanceKitSync server

Receives transaction packets from the iOS app and stores them in SQLite.

## Run locally

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
FKS_TOKEN=dev-token FKS_DB_PATH=./data/dev.db uvicorn app.main:app --port 8501
```

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `FKS_TOKEN` | *(required)* | Bearer token. The server refuses to start without it. |
| `FKS_DB_PATH` | `/data/financekitsync.db` | SQLite file path. |

## API

| Method | Path | Auth | |
|---|---|---|---|
| GET | `/health` | — | `{"status":"ok","schema_version":1}` |
| POST | `/financekit-sync` | Bearer | Accept a packet, idempotent upsert |
| GET | `/accounts` | Bearer | Current balances |
| GET | `/transactions?since=&limit=` | Bearer | Newest first, `limit` ≤ 1000 |
| GET | `/stats` | Bearer | Row counts |

`/health` is intentionally unauthenticated so the app's onboarding can verify
the address before a token is entered. It returns nothing useful to a scanner.
There are no `/docs` or `/openapi.json` routes — this endpoint is on the public
internet and shouldn't advertise itself.

## Tailnet address

`https://box.tail590aa.ts.net:8501` — Tailscale Serve, tailnet-only, on a port
this service owns. It is deliberately not sharing :8443 with box-api and the
web UI: a serve mount at `/` replaces whatever was there, so deploying here
used to evict the web UI.

## Deploy to `box`

See [`../docs/workstream-server.md`](../docs/workstream-server.md) for the full
procedure. Short version:

```bash
./deploy.sh
```

## Backups

The entire dataset is one SQLite file. Back it up with the online backup API
rather than `cp` — a plain copy of a WAL-mode database mid-write is not
guaranteed consistent:

```bash
sqlite3 /opt/financekitsync/data/financekitsync.db ".backup '/tmp/fks-backup.db'"
```
