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
| `FKS_NOTIFY_URL` | *(unset)* | Box API relay for identity tripwires, e.g. `http://127.0.0.1:8444/notify`. Unset: logged only. |
| `FKS_NOTIFY_API_KEY` | *(unset)* | Box API key sent as `X-API-Key` to the relay. |
| `FKS_ACCOUNT_STALE_HOURS` | `24` | How long an account's install must be silent before a new device may take it over. |
| `FKS_TRIPWIRE_BURST` | `3` | Unmatched old-dated rows in one upload that count as a re-key box missed. |

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
There are no `/docs` or `/openapi.json` routes. This process is reachable only
on localhost; Box API owns network exposure.

## Stable identity across devices

FinanceKit IDs are device-local: a new phone, reinstall or re-authorisation can
re-key accounts and transactions box already holds. Box owns identity instead.
The `id` and `account_id` it serves are *canonical*: the first device ID it saw
for that record. Every upload carries the app's `device_install_id` (a
per-install UUID kept in the Keychain, never synced) and resolves through
`account_aliases` / `transaction_aliases`:

- A known device ID (from any install) is an update to its canonical row.
- An unknown transaction on a known account is matched to an existing row
  from a *different* install by fingerprint: wallet date to the second, amount,
  currency, credit/debit, type and description. Identical fingerprints pair
  one to one in date order; a surplus is a new row.
- An unknown account is aliased onto an existing one only when institution and
  name match, the existing account's install has been silent for
  `FKS_ACCOUNT_STALE_HOURS`, and fingerprints overlap strongly. Otherwise it
  and its transactions are held out of the API and a notification is sent.
- A burst of unmatched transactions dated inside history box already holds is
  held the same way.

`metadata.wallet` carries the latest device payload with its
`transaction_id` and `account_id` rewritten to canonical. Resolve holds with
`./financekit` on box:

```bash
./financekit pending
./financekit alias-account <device_account_id> <canonical_account_id>
./financekit release-held <device_account_id> [--drop]
```

### One-time repair (2026-10 phone switch)

```bash
docker exec financekitsync python -m app.repair            # dry run
docker exec financekitsync python -m app.repair --apply
```

Both take a backup and write `report.txt` beside it in
`data/repair-<stamp>/`. Pairs to merge default to accounts sharing institution
and name; pass `--merge 99B1EC23:0271CEE9 --merge 373EA1D6:CC61535D` to be
explicit.

## Tests

```bash
pip install -r requirements.txt pytest httpx
python -m pytest tests
```

## Network boundary

The container uses host networking and binds `127.0.0.1:8501` only. There is deliberately no Tailscale listener
for this port. The iPhone and downstream consumers use Box API's namespaced
endpoint: `https://$FKS_HOST:8443/api/financekit`.

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
