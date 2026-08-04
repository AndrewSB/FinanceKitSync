"""SQLite storage for FinanceKitSync packets.

Deliberately boring: one file, WAL mode, two tables, upsert-on-conflict. The
FinanceKit transaction UUID is the primary key, which is what makes replays
free — the client is allowed to lose its acknowledgement ledger and re-send
everything without creating duplicates.
"""

from __future__ import annotations

import json
import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    institution  TEXT NOT NULL,
    balance      REAL NOT NULL,
    currency     TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS transactions (
    id            TEXT PRIMARY KEY,
    account_id    TEXT NOT NULL,
    date          TEXT NOT NULL,
    amount        REAL NOT NULL,
    currency      TEXT NOT NULL,
    payee         TEXT NOT NULL,
    status        TEXT NOT NULL,
    notes         TEXT NOT NULL,
    category      TEXT NOT NULL,
    metadata      TEXT NOT NULL,
    first_seen_at TEXT NOT NULL,
    updated_at    TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_transactions_date
    ON transactions (date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_account
    ON transactions (account_id, date DESC);
"""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self, path: Path):
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # One writer at a time. SQLite serializes writes anyway; holding an
        # explicit lock keeps the "did it insert or update" counting honest
        # under concurrent requests.
        self._lock = threading.Lock()
        with self._connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA synchronous=NORMAL")
            conn.executescript(SCHEMA)

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self.path, timeout=30, isolation_level=None)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    # -- writes ---------------------------------------------------------

    def upsert_packet(
        self, accounts: list[dict[str, Any]], transactions: list[dict[str, Any]]
    ) -> dict[str, int]:
        """Applies one packet atomically. Returns insert/update counts."""
        now = _now()
        inserted = 0
        updated = 0

        with self._lock, self._connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                for account in accounts:
                    conn.execute(
                        """
                        INSERT INTO accounts (id, name, institution, balance, currency, updated_at)
                        VALUES (:id, :name, :institution, :balance, :currency, :updated_at)
                        ON CONFLICT(id) DO UPDATE SET
                            name        = excluded.name,
                            institution = excluded.institution,
                            balance     = excluded.balance,
                            currency    = excluded.currency,
                            updated_at  = excluded.updated_at
                        """,
                        {**account, "updated_at": now},
                    )

                if transactions:
                    ids = [t["id"] for t in transactions]
                    # Chunked so a 500-row batch can't blow past SQLite's
                    # default 999-variable limit on older builds.
                    known: set[str] = set()
                    for start in range(0, len(ids), 500):
                        chunk = ids[start : start + 500]
                        placeholders = ",".join("?" * len(chunk))
                        rows = conn.execute(
                            f"SELECT id FROM transactions WHERE id IN ({placeholders})",
                            chunk,
                        ).fetchall()
                        known.update(row["id"] for row in rows)

                    for txn in transactions:
                        is_new = txn["id"] not in known
                        conn.execute(
                            """
                            INSERT INTO transactions (
                                id, account_id, date, amount, currency, payee,
                                status, notes, category, metadata,
                                first_seen_at, updated_at
                            ) VALUES (
                                :id, :account_id, :date, :amount, :currency, :payee,
                                :status, :notes, :category, :metadata,
                                :first_seen_at, :updated_at
                            )
                            ON CONFLICT(id) DO UPDATE SET
                                account_id = excluded.account_id,
                                date       = excluded.date,
                                amount     = excluded.amount,
                                currency   = excluded.currency,
                                payee      = excluded.payee,
                                status     = excluded.status,
                                notes      = excluded.notes,
                                category   = excluded.category,
                                metadata   = excluded.metadata,
                                updated_at = excluded.updated_at
                            """,
                            {
                                "id": txn["id"],
                                "account_id": txn["account_id"],
                                "date": txn["date"],
                                "amount": txn["amount"],
                                "currency": txn["currency"],
                                "payee": txn["payee"],
                                "status": txn["status"],
                                "notes": txn["notes"],
                                "category": txn["category"],
                                "metadata": json.dumps(
                                    txn["metadata"], separators=(",", ":")
                                ),
                                # first_seen_at is only used on insert; the
                                # ON CONFLICT clause deliberately leaves it be.
                                "first_seen_at": now,
                                "updated_at": now,
                            },
                        )
                        if is_new:
                            inserted += 1
                        else:
                            updated += 1

                conn.execute("COMMIT")
            except Exception:
                conn.execute("ROLLBACK")
                raise

        return {"inserted": inserted, "updated": updated}

    # -- reads ----------------------------------------------------------

    def list_accounts(self) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM accounts ORDER BY name").fetchall()
        return [dict(row) for row in rows]

    def list_transactions(
        self, since: str | None = None, limit: int = 100
    ) -> list[dict[str, Any]]:
        query = "SELECT * FROM transactions"
        params: list[Any] = []
        if since:
            query += " WHERE date >= ?"
            params.append(since)
        query += " ORDER BY date DESC LIMIT ?"
        params.append(limit)

        with self._connect() as conn:
            rows = conn.execute(query, params).fetchall()

        result = []
        for row in rows:
            item = dict(row)
            item["metadata"] = json.loads(item["metadata"])
            result.append(item)
        return result

    def counts(self) -> dict[str, int]:
        with self._connect() as conn:
            accounts = conn.execute("SELECT COUNT(*) AS n FROM accounts").fetchone()["n"]
            transactions = conn.execute(
                "SELECT COUNT(*) AS n FROM transactions"
            ).fetchone()["n"]
        return {"accounts": accounts, "transactions": transactions}
