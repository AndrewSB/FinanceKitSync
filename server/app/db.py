"""SQLite storage for FinanceKitSync packets.

Deliberately boring: one file, WAL mode, upsert-on-conflict.

FinanceKit IDs are device-local, so the ``accounts`` and ``transactions``
tables are keyed by a *canonical* ID that box owns: the first device ID it ever
saw for that record. Every device ID resolves through ``account_aliases`` /
``transaction_aliases`` first, keyed by the install that sent it. Replays stay
free (a known device ID is an update, never a second row), and a phone switch
that re-keys history lands on the rows box already holds instead of
duplicating them. See ``identity.py`` for the fingerprint that recognises a
re-keyed row.

An unknown device account is never trusted blindly. It is aliased onto an
existing account only when the evidence is strong (see
``_account_verdict``); otherwise it and its transactions wait in
``pending_account_matches`` / ``held_transactions``, out of the API, until
``financekit alias-account`` resolves them.
"""

from __future__ import annotations

import json
import os
import sqlite3
import threading
from collections import Counter, defaultdict
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator

from .identity import (
    LEGACY_INSTALL,
    _decimal,
    _second,
    fingerprint,
    normalise_name,
    rewrite_wallet_ids,
)

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

-- One row per app install. first_upload_at anchors the tripwire.
CREATE TABLE IF NOT EXISTS installs (
    id              TEXT PRIMARY KEY,
    first_upload_at TEXT NOT NULL,
    last_upload_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS canonical_accounts (
    id         TEXT PRIMARY KEY,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS canonical_transactions (
    id          TEXT PRIMARY KEY,
    account_id  TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    created_at  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_canonical_transactions_fingerprint
    ON canonical_transactions (account_id, fingerprint);

CREATE TABLE IF NOT EXISTS account_aliases (
    device_install_id    TEXT NOT NULL,
    device_account_id    TEXT NOT NULL,
    canonical_account_id TEXT NOT NULL,
    created_at           TEXT NOT NULL,
    last_seen_at         TEXT NOT NULL,
    PRIMARY KEY (device_install_id, device_account_id)
);
CREATE INDEX IF NOT EXISTS idx_account_aliases_device
    ON account_aliases (device_account_id);
CREATE INDEX IF NOT EXISTS idx_account_aliases_canonical
    ON account_aliases (canonical_account_id);

CREATE TABLE IF NOT EXISTS transaction_aliases (
    device_install_id        TEXT NOT NULL,
    device_transaction_id    TEXT NOT NULL,
    canonical_transaction_id TEXT NOT NULL,
    created_at               TEXT NOT NULL,
    PRIMARY KEY (device_install_id, device_transaction_id)
);
CREATE INDEX IF NOT EXISTS idx_transaction_aliases_device
    ON transaction_aliases (device_transaction_id);
CREATE INDEX IF NOT EXISTS idx_transaction_aliases_canonical
    ON transaction_aliases (canonical_transaction_id, device_install_id);

-- Unknown device accounts box would not alias on its own.
CREATE TABLE IF NOT EXISTS pending_account_matches (
    device_install_id TEXT NOT NULL,
    device_account_id TEXT NOT NULL,
    account           TEXT NOT NULL,
    reason            TEXT NOT NULL,
    notified          INTEGER NOT NULL DEFAULT 0,
    created_at        TEXT NOT NULL,
    updated_at        TEXT NOT NULL,
    PRIMARY KEY (device_install_id, device_account_id)
);

-- Device rows kept out of the API. kind 'account': their account is pending.
-- kind 'tripwire': unknown history that looked like a re-key box could not match.
CREATE TABLE IF NOT EXISTS held_transactions (
    device_install_id     TEXT NOT NULL,
    device_transaction_id TEXT NOT NULL,
    device_account_id     TEXT NOT NULL,
    kind                  TEXT NOT NULL,
    payload               TEXT NOT NULL,
    created_at            TEXT NOT NULL,
    updated_at            TEXT NOT NULL,
    PRIMARY KEY (device_install_id, device_transaction_id)
);
"""

# An account whose aliases have all been silent this long has "stopped
# receiving updates from its own install" and may be taken over.
STALE_AFTER = timedelta(hours=float(os.environ.get("FKS_ACCOUNT_STALE_HOURS", "24")))
# Strong overlap: at least this many shared fingerprints, covering at least
# this share of the new device's rows in the window both cover.
MIN_OVERLAP = 3
OVERLAP_RATIO = 0.8
# This many unmatched rows dated inside history box already holds, from one
# upload, is a re-key box failed to recognise rather than new spending.
TRIPWIRE_BURST = int(os.environ.get("FKS_TRIPWIRE_BURST", "3"))


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _dumps(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"))


class IdentityError(Exception):
    """A manual identity operation that cannot be applied as asked."""


@dataclass
class _Upload:
    """State for one packet while its transaction is open."""

    conn: sqlite3.Connection
    install: str
    now: str
    first_upload_at: str
    inserted: int = 0
    updated: int = 0
    events: list[str] = field(default_factory=list)


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
            conn.execute("BEGIN IMMEDIATE")
            self._bootstrap(conn)
            conn.execute("COMMIT")

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self.path, timeout=30, isolation_level=None)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        """A write transaction for maintenance tools. Rolls back on error."""
        with self._lock, self._connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                yield conn
                conn.execute("COMMIT")
            except BaseException:
                conn.execute("ROLLBACK")
                raise

    def _bootstrap(self, conn: sqlite3.Connection) -> None:
        """Registers rows stored before identity tracking existed.

        Each becomes its own canonical record, aliased under the legacy
        install. A no-op once every row is registered.
        """
        first = conn.execute("SELECT MIN(first_seen_at) AS t FROM transactions").fetchone()["t"]
        stamp = first or _now()
        conn.execute(
            "INSERT OR IGNORE INTO installs (id, first_upload_at, last_upload_at) VALUES (?, ?, ?)",
            (LEGACY_INSTALL, stamp, stamp),
        )
        conn.execute(
            """
            INSERT INTO canonical_accounts (id, created_at)
            SELECT id, updated_at FROM accounts
            WHERE id NOT IN (SELECT id FROM canonical_accounts)
            """
        )
        conn.execute(
            """
            INSERT OR IGNORE INTO account_aliases
                (device_install_id, device_account_id, canonical_account_id, created_at, last_seen_at)
            SELECT ?, id, id, updated_at, updated_at FROM accounts a
            WHERE NOT EXISTS (SELECT 1 FROM account_aliases x WHERE x.canonical_account_id = a.id)
            """,
            (LEGACY_INSTALL,),
        )
        rows = conn.execute(
            """
            SELECT * FROM transactions
            WHERE id NOT IN (SELECT id FROM canonical_transactions)
            """
        ).fetchall()
        for row in rows:
            txn = dict(row)
            txn["metadata"] = json.loads(txn["metadata"])
            conn.execute(
                "INSERT INTO canonical_transactions (id, account_id, fingerprint, created_at) VALUES (?, ?, ?, ?)",
                (txn["id"], txn["account_id"], fingerprint(txn), txn["first_seen_at"]),
            )
            conn.execute(
                """
                INSERT OR IGNORE INTO transaction_aliases
                    (device_install_id, device_transaction_id, canonical_transaction_id, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (LEGACY_INSTALL, txn["id"], txn["id"], txn["first_seen_at"]),
            )

    # -- writes ---------------------------------------------------------

    def upsert_packet(
        self,
        accounts: list[dict[str, Any]],
        transactions: list[dict[str, Any]],
        install_id: str | None = None,
    ) -> dict[str, Any]:
        """Applies one packet atomically.

        Returns insert/update/held counts and the identity events worth a
        notification. ``inserted + updated + held`` is every transaction in the
        packet.
        """
        install = install_id or LEGACY_INSTALL
        now = _now()

        with self._lock, self._connect() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                conn.execute(
                    """
                    INSERT INTO installs (id, first_upload_at, last_upload_at) VALUES (?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET last_upload_at = excluded.last_upload_at
                    """,
                    (install, now, now),
                )
                first = conn.execute(
                    "SELECT first_upload_at FROM installs WHERE id = ?", (install,)
                ).fetchone()["first_upload_at"]
                up = _Upload(conn, install, now, first)

                resolved: dict[str, str | None] = {}
                for account in accounts:
                    resolved[account["id"]] = self._resolve_account(up, account)

                by_account: dict[str, list[dict[str, Any]]] = defaultdict(list)
                for txn in transactions:
                    by_account[txn["account_id"]].append(txn)
                for device_account, txns in by_account.items():
                    if device_account not in resolved:
                        resolved[device_account] = self._account_alias(up, device_account)
                    canonical = resolved[device_account]
                    if canonical is None:
                        for txn in txns:
                            self._hold(up, txn, "account")
                    else:
                        self._apply_transactions(up, canonical, txns)

                for device_account, canonical in resolved.items():
                    if canonical is None:
                        self._evaluate_pending_account(up, device_account)

                held = 0
                for txn in transactions:
                    held += conn.execute(
                        """
                        SELECT COUNT(*) AS n FROM held_transactions
                        WHERE device_install_id = ? AND device_transaction_id = ?
                        """,
                        (install, txn["id"]),
                    ).fetchone()["n"]

                conn.execute("COMMIT")
            except Exception:
                conn.execute("ROLLBACK")
                raise

        return {
            "inserted": up.inserted,
            "updated": up.updated,
            "held": held,
            "events": up.events,
        }

    # -- accounts ---------------------------------------------------------

    def _account_alias(self, up: _Upload, device_account: str) -> str | None:
        """The canonical account for a device account ID, if box knows it.

        A device ID first sent by another install (or before install IDs
        existed) is the same FinanceKit account, so it is adopted for this
        install as well.
        """
        conn = up.conn
        row = conn.execute(
            """
            SELECT canonical_account_id FROM account_aliases
            WHERE device_install_id = ? AND device_account_id = ?
            """,
            (up.install, device_account),
        ).fetchone()
        if row is None:
            row = conn.execute(
                """
                SELECT canonical_account_id FROM account_aliases
                WHERE device_account_id = ? ORDER BY created_at LIMIT 1
                """,
                (device_account,),
            ).fetchone()
            if row is None:
                return None
            self._add_account_alias(conn, up.install, device_account, row[0], up.now)
        conn.execute(
            """
            UPDATE account_aliases SET last_seen_at = ?
            WHERE device_install_id = ? AND device_account_id = ?
            """,
            (up.now, up.install, device_account),
        )
        return row[0]

    @staticmethod
    def _add_account_alias(
        conn: sqlite3.Connection, install: str, device_account: str, canonical: str, now: str
    ) -> None:
        conn.execute(
            """
            INSERT INTO account_aliases
                (device_install_id, device_account_id, canonical_account_id, created_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(device_install_id, device_account_id) DO UPDATE SET
                canonical_account_id = excluded.canonical_account_id,
                last_seen_at         = excluded.last_seen_at
            """,
            (install, device_account, canonical, now, now),
        )

    @staticmethod
    def _write_account(
        conn: sqlite3.Connection, canonical: str, account: dict[str, Any], now: str
    ) -> None:
        # Balance and updated_at come from whichever alias reported last.
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
            {**account, "id": canonical, "updated_at": now},
        )

    def _resolve_account(self, up: _Upload, account: dict[str, Any]) -> str | None:
        canonical = self._account_alias(up, account["id"])
        if canonical is not None:
            self._write_account(up.conn, canonical, account, up.now)
            return canonical
        up.conn.execute(
            """
            INSERT INTO pending_account_matches
                (device_install_id, device_account_id, account, reason, created_at, updated_at)
            VALUES (?, ?, ?, 'unevaluated', ?, ?)
            ON CONFLICT(device_install_id, device_account_id) DO UPDATE SET
                account    = excluded.account,
                updated_at = excluded.updated_at
            """,
            (up.install, account["id"], _dumps(account), up.now, up.now),
        )
        return None

    def _evaluate_pending_account(self, up: _Upload, device_account: str) -> None:
        """Aliases, creates or keeps holding an unknown device account."""
        conn = up.conn
        pending = conn.execute(
            """
            SELECT * FROM pending_account_matches
            WHERE device_install_id = ? AND device_account_id = ?
            """,
            (up.install, device_account),
        ).fetchone()
        if pending is None:
            # Transactions for an account the packet did not describe. They
            # stay held until the account itself arrives.
            return
        account = json.loads(pending["account"])
        label = f"{normalise_name(account['name'])} ({account['institution']})"
        held = self._held(conn, up.install, device_account, "account")

        candidates = [
            row["id"]
            for row in conn.execute("SELECT id, name, institution FROM accounts").fetchall()
            if row["institution"] == account["institution"]
            and normalise_name(row["name"]) == normalise_name(account["name"])
        ]
        if not candidates:
            # Nothing it could be a re-key of: a genuinely new account.
            self._adopt_account(up, device_account, device_account, account, created=True)
            up.events.append(f"New FinanceKit account {label} from install {up.install[:8]}.")
            return

        verdicts = {c: self._account_verdict(up, c, held) for c in candidates}
        passing = [c for c, verdict in verdicts.items() if verdict is None]
        if len(passing) == 1:
            self._adopt_account(up, device_account, passing[0], account, created=False)
            up.events.append(
                f"FinanceKit account {label} from install {up.install[:8]} "
                f"recognised as {passing[0]} (device ID {device_account})."
            )
            return

        if len(passing) > 1:
            reason, waiting = f"{len(passing)} accounts match equally", False
        else:
            reason = "; ".join(f"{c}: {v[1]}" for c, v in verdicts.items())
            waiting = all(v[0] == "waiting" for v in verdicts.values())
        conn.execute(
            """
            UPDATE pending_account_matches SET reason = ?, updated_at = ?
            WHERE device_install_id = ? AND device_account_id = ?
            """,
            (reason, up.now, up.install, device_account),
        )
        if not waiting and not pending["notified"]:
            conn.execute(
                """
                UPDATE pending_account_matches SET notified = 1
                WHERE device_install_id = ? AND device_account_id = ?
                """,
                (up.install, device_account),
            )
            up.events.append(
                f"Holding FinanceKit account {label} (device ID {device_account}, "
                f"install {up.install[:8]}) and {len(held)} transaction(s): {reason}. "
                f"Resolve with: financekit alias-account {device_account} <canonical_account_id>"
            )

    def _account_verdict(
        self, up: _Upload, canonical: str, held: list[dict[str, Any]]
    ) -> tuple[str, str] | None:
        """None when ``held`` is strongly the same account as ``canonical``."""
        conn = up.conn
        cutoff = (datetime.fromisoformat(up.now) - STALE_AFTER).isoformat()
        live = conn.execute(
            """
            SELECT device_install_id FROM account_aliases
            WHERE canonical_account_id = ? AND last_seen_at > ?
            """,
            (canonical, cutoff),
        ).fetchall()
        if live:
            return ("live", f"still updated by install {live[0][0][:8]}")
        if not held:
            return ("waiting", "no transactions yet to compare")

        existing = conn.execute(
            """
            SELECT c.fingerprint, t.date FROM canonical_transactions c
            JOIN transactions t ON t.id = c.id
            WHERE c.account_id = ?
            """,
            (canonical,),
        ).fetchall()
        if not existing:
            return ("weak", "no history to compare")
        mine = [(fingerprint(t), _second(t["date"])) for t in held]
        theirs = [(row["fingerprint"], _second(row["date"])) for row in existing]
        low = max(min(d for _, d in mine), min(d for _, d in theirs))
        high = min(max(d for _, d in mine), max(d for _, d in theirs))
        mine_w = Counter(f for f, d in mine if low <= d <= high)
        theirs_w = Counter(f for f, d in theirs if low <= d <= high)
        total = sum(mine_w.values())
        shared = sum((mine_w & theirs_w).values())
        if total == 0:
            return ("weak", "histories do not overlap")
        if shared >= MIN_OVERLAP and shared / total >= OVERLAP_RATIO:
            return None
        return ("weak", f"only {shared} of {total} overlapping transactions match")

    def _adopt_account(
        self,
        up: _Upload,
        device_account: str,
        canonical: str,
        account: dict[str, Any],
        created: bool,
    ) -> None:
        conn = up.conn
        if created:
            conn.execute(
                "INSERT INTO canonical_accounts (id, created_at) VALUES (?, ?)",
                (canonical, up.now),
            )
        self._add_account_alias(conn, up.install, device_account, canonical, up.now)
        self._write_account(conn, canonical, account, up.now)
        conn.execute(
            """
            DELETE FROM pending_account_matches
            WHERE device_install_id = ? AND device_account_id = ?
            """,
            (up.install, device_account),
        )
        held = self._held(conn, up.install, device_account, "account")
        conn.execute(
            """
            DELETE FROM held_transactions
            WHERE device_install_id = ? AND device_account_id = ? AND kind = 'account'
            """,
            (up.install, device_account),
        )
        self._apply_transactions(up, canonical, held)

    # -- transactions -----------------------------------------------------

    @staticmethod
    def _held(
        conn: sqlite3.Connection, install: str, device_account: str, kind: str
    ) -> list[dict[str, Any]]:
        rows = conn.execute(
            """
            SELECT payload FROM held_transactions
            WHERE device_install_id = ? AND device_account_id = ? AND kind = ?
            ORDER BY created_at, rowid
            """,
            (install, device_account, kind),
        ).fetchall()
        return [json.loads(row["payload"]) for row in rows]

    def _hold(self, up: _Upload, txn: dict[str, Any], kind: str) -> None:
        up.conn.execute(
            """
            INSERT INTO held_transactions
                (device_install_id, device_transaction_id, device_account_id,
                 kind, payload, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(device_install_id, device_transaction_id) DO UPDATE SET
                payload    = excluded.payload,
                updated_at = excluded.updated_at
            """,
            (up.install, txn["id"], txn["account_id"], kind, _dumps(txn), up.now, up.now),
        )

    def _transaction_alias(self, up: _Upload, device_txn: str) -> str | None:
        conn = up.conn
        row = conn.execute(
            """
            SELECT canonical_transaction_id FROM transaction_aliases
            WHERE device_install_id = ? AND device_transaction_id = ?
            """,
            (up.install, device_txn),
        ).fetchone()
        if row is not None:
            return row[0]
        # Same FinanceKit ID from another install is the same row.
        row = conn.execute(
            """
            SELECT canonical_transaction_id FROM transaction_aliases
            WHERE device_transaction_id = ? ORDER BY created_at LIMIT 1
            """,
            (device_txn,),
        ).fetchone()
        if row is None:
            return None
        self._add_transaction_alias(conn, up.install, device_txn, row[0], up.now)
        return row[0]

    @staticmethod
    def _add_transaction_alias(
        conn: sqlite3.Connection, install: str, device_txn: str, canonical: str, now: str
    ) -> None:
        conn.execute(
            """
            INSERT OR REPLACE INTO transaction_aliases
                (device_install_id, device_transaction_id, canonical_transaction_id, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (install, device_txn, canonical, now),
        )

    def _apply_transactions(
        self, up: _Upload, account: str, txns: list[dict[str, Any]]
    ) -> None:
        """Writes device rows for a resolved account under canonical IDs."""
        conn = up.conn
        unknown: list[dict[str, Any]] = []
        for txn in txns:
            still_held = conn.execute(
                """
                SELECT 1 FROM held_transactions
                WHERE device_install_id = ? AND device_transaction_id = ?
                """,
                (up.install, txn["id"]),
            ).fetchone()
            if still_held:
                self._hold(up, txn, "tripwire")
                continue
            canonical = self._transaction_alias(up, txn["id"])
            if canonical is None:
                unknown.append(txn)
            else:
                # Includes pending -> posted: same device ID, new date/amount.
                self._write_transaction(up, canonical, account, txn)
                up.updated += 1

        # Re-keyed rows: pair identical fingerprints one-to-one, in date
        # order, against canonical rows no alias from this install claims yet.
        # That makes a genuine repeat charge from this install a new row, and
        # a surplus a new row, never a merge.
        groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for txn in unknown:
            groups[fingerprint(txn)].append(txn)
        unmatched: list[dict[str, Any]] = []
        for fp, group in groups.items():
            group.sort(key=lambda t: t["date"])
            candidates = conn.execute(
                """
                SELECT c.id FROM canonical_transactions c
                JOIN transactions t ON t.id = c.id
                WHERE c.account_id = ? AND c.fingerprint = ?
                  AND NOT EXISTS (
                      SELECT 1 FROM transaction_aliases a
                      WHERE a.canonical_transaction_id = c.id AND a.device_install_id = ?
                  )
                ORDER BY t.date, t.first_seen_at, c.rowid
                """,
                (account, fp, up.install),
            ).fetchall()
            for txn, row in zip(group, candidates):
                self._add_transaction_alias(conn, up.install, txn["id"], row["id"], up.now)
                self._write_transaction(up, row["id"], account, txn)
                up.updated += 1
            unmatched.extend(group[len(candidates):])

        suspicious = self._tripwire(up, account, unmatched)
        for txn in unmatched:
            if txn["id"] in suspicious:
                self._hold(up, txn, "tripwire")
            else:
                self._create_transaction(up, account, txn)

    def _tripwire(
        self, up: _Upload, account: str, unmatched: list[dict[str, Any]]
    ) -> set[str]:
        """IDs of unmatched rows that look like history box already holds.

        Rows dated before this install's first upload *and* inside the history
        other installs already gave box for this account should have matched
        something. A burst of them means a re-key box did not recognise.
        """
        if len(unmatched) < TRIPWIRE_BURST:
            return set()
        known_until = up.conn.execute(
            """
            SELECT MAX(t.date) FROM transactions t
            WHERE t.account_id = ? AND EXISTS (
                SELECT 1 FROM transaction_aliases a
                WHERE a.canonical_transaction_id = t.id AND a.device_install_id != ?
            )
            """,
            (account, up.install),
        ).fetchone()[0]
        if known_until is None:
            return set()
        cutoff = min(_second(up.first_upload_at), _second(known_until))
        suspicious = {t["id"] for t in unmatched if _second(t["date"]) < cutoff}
        if len(suspicious) < TRIPWIRE_BURST:
            return set()
        name = up.conn.execute("SELECT name FROM accounts WHERE id = ?", (account,)).fetchone()
        up.events.append(
            f"Holding {len(suspicious)} unrecognised FinanceKit transaction(s) on "
            f"{normalise_name(name[0]) if name else account} from install {up.install[:8]}, "
            f"dated inside history box already has. Review with: financekit held"
        )
        return suspicious

    def _create_transaction(self, up: _Upload, account: str, txn: dict[str, Any]) -> None:
        up.conn.execute(
            """
            INSERT INTO canonical_transactions (id, account_id, fingerprint, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (txn["id"], account, fingerprint(txn), up.now),
        )
        self._add_transaction_alias(up.conn, up.install, txn["id"], txn["id"], up.now)
        self._write_transaction(up, txn["id"], account, txn)
        up.inserted += 1

    @staticmethod
    def _write_transaction(
        up: _Upload, canonical: str, account: str, txn: dict[str, Any]
    ) -> None:
        conn = up.conn
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
                "id": canonical,
                "account_id": account,
                "date": txn["date"],
                "amount": txn["amount"],
                "currency": txn["currency"],
                "payee": txn["payee"],
                "status": txn["status"],
                "notes": txn["notes"],
                "category": txn["category"],
                "metadata": _dumps(rewrite_wallet_ids(txn["metadata"], canonical, account)),
                # first_seen_at is only used on insert; the ON CONFLICT
                # clause deliberately leaves the canonical row's be.
                "first_seen_at": up.now,
                "updated_at": up.now,
            },
        )
        conn.execute(
            "UPDATE canonical_transactions SET fingerprint = ?, account_id = ? WHERE id = ?",
            (fingerprint(txn), account, canonical),
        )

    # -- manual resolution ------------------------------------------------

    def alias_account(self, device_account: str, canonical: str) -> dict[str, Any]:
        """``financekit alias-account``: resolve a held device account by hand.

        A device account still held is aliased onto ``canonical`` and its held
        transactions are matched as on upload. A device account that already
        became its own canonical account is merged into ``canonical``.
        """
        with self.transaction() as conn:
            if not conn.execute(
                "SELECT 1 FROM canonical_accounts WHERE id = ?", (canonical,)
            ).fetchone():
                raise IdentityError(f"{canonical} is not a canonical account")
            pending = conn.execute(
                "SELECT * FROM pending_account_matches WHERE device_account_id = ?",
                (device_account,),
            ).fetchall()
            if pending:
                now = _now()
                result = {"resolved": [], "inserted": 0, "updated": 0, "held": 0}
                for row in pending:
                    first = conn.execute(
                        "SELECT first_upload_at FROM installs WHERE id = ?",
                        (row["device_install_id"],),
                    ).fetchone()[0]
                    up = _Upload(conn, row["device_install_id"], now, first)
                    self._adopt_account(
                        up, device_account, canonical, json.loads(row["account"]), created=False
                    )
                    result["resolved"].append(row["device_install_id"])
                    result["inserted"] += up.inserted
                    result["updated"] += up.updated
                result["held"] = conn.execute(
                    "SELECT COUNT(*) FROM held_transactions WHERE device_account_id = ?",
                    (device_account,),
                ).fetchone()[0]
                return result
            source = conn.execute(
                "SELECT canonical_account_id FROM account_aliases WHERE device_account_id = ? LIMIT 1",
                (device_account,),
            ).fetchone()
            if source is None:
                raise IdentityError(f"box has never seen device account {device_account}")
            if source[0] == canonical:
                raise IdentityError(f"{device_account} already resolves to {canonical}")
            return merge_accounts(conn, source[0], canonical, cutoff=None)

    def list_pending(self) -> dict[str, Any]:
        with self._connect() as conn:
            accounts = [
                {**dict(row), "account": json.loads(row["account"])}
                for row in conn.execute(
                    "SELECT * FROM pending_account_matches ORDER BY created_at"
                ).fetchall()
            ]
            held = [
                dict(row)
                for row in conn.execute(
                    """
                    SELECT device_install_id, device_account_id, kind, COUNT(*) AS n,
                           MIN(created_at) AS since
                    FROM held_transactions
                    GROUP BY device_install_id, device_account_id, kind
                    """
                ).fetchall()
            ]
        return {"accounts": accounts, "held_transactions": held}

    def release_held(self, device_account: str, drop: bool = False) -> int:
        """Accepts (or drops) tripwire-held rows as genuinely new transactions."""
        with self.transaction() as conn:
            rows = conn.execute(
                """
                SELECT * FROM held_transactions
                WHERE device_account_id = ? AND kind = 'tripwire'
                ORDER BY created_at, rowid
                """,
                (device_account,),
            ).fetchall()
            conn.execute(
                "DELETE FROM held_transactions WHERE device_account_id = ? AND kind = 'tripwire'",
                (device_account,),
            )
            if drop:
                return len(rows)
            now = _now()
            for row in rows:
                up = _Upload(conn, row["device_install_id"], now, now)
                txn = json.loads(row["payload"])
                account = self._account_alias(up, txn["account_id"])
                if account is None:
                    raise IdentityError(f"account {txn['account_id']} is not resolved")
                if self._transaction_alias(up, txn["id"]) is None:
                    self._create_transaction(up, account, txn)
            return len(rows)

    # -- reads ----------------------------------------------------------

    def list_accounts(self) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM accounts ORDER BY name").fetchall()
        return [dict(row) for row in rows]

    def list_transactions(
        self,
        since: str | None = None,
        limit: int = 100,
        until: str | None = None,
    ) -> list[dict[str, Any]]:
        """Newest first, within an optional window [since, until], both inclusive.

        ``until`` lets a caller page backwards through more rows than ``limit``
        by passing the oldest date it just received. It is *inclusive* on
        purpose: exclusive would drop any row sharing that exact timestamp that
        did not fit in the previous page, silently and undetectably. Inclusive
        re-sends the boundary rows instead, which the caller discards by id —
        a page of overlap is cheap, a lost transaction is not.

        Dates are stored as full ISO-8601 timestamps and compared as strings,
        which orders correctly and lets a date-only bound like ``2026-08-01``
        mean the start of that day.
        """
        query = "SELECT * FROM transactions"
        clauses: list[str] = []
        params: list[Any] = []
        if since:
            clauses.append("date >= ?")
            params.append(since)
        if until:
            clauses.append("date <= ?")
            params.append(until)
        if clauses:
            query += " WHERE " + " AND ".join(clauses)
        query += " ORDER BY date DESC, id LIMIT ?"
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
            pending = conn.execute(
                "SELECT COUNT(*) AS n FROM pending_account_matches"
            ).fetchone()["n"]
            held = conn.execute("SELECT COUNT(*) AS n FROM held_transactions").fetchone()["n"]
        return {
            "accounts": accounts,
            "transactions": transactions,
            "pending_accounts": pending,
            "held_transactions": held,
        }


# -- merging existing canonical records ------------------------------------


def _rows(conn: sqlite3.Connection, where: str, params: tuple[Any, ...]) -> list[dict[str, Any]]:
    rows = conn.execute(
        f"""
        SELECT t.*, c.fingerprint FROM transactions t
        JOIN canonical_transactions c ON c.id = t.id
        WHERE {where}
        ORDER BY t.date, t.first_seen_at, t.id
        """,
        params,
    ).fetchall()
    return [dict(row) for row in rows]


def _loose_key(row: dict[str, Any]) -> tuple[str, ...]:
    """The fingerprint's fields, minus the description."""
    wallet = json.loads(row["metadata"]).get("wallet") or {}
    amount = wallet.get("amount") or {}
    return (
        _second(wallet.get("transaction_date", row["date"])),
        _decimal(amount.get("value", row["amount"])),
        str(amount.get("currency", row["currency"])),
        str(wallet.get("credit_debit_indicator", "")),
        str(wallet.get("transaction_type", "")),
    )


def _fold(
    conn: sqlite3.Connection, new: dict[str, Any], old: dict[str, Any], target: str
) -> None:
    """Makes ``new`` an alias of ``old`` and deletes the newer copy."""
    conn.execute(
        "UPDATE transaction_aliases SET canonical_transaction_id = ? WHERE canonical_transaction_id = ?",
        (old["id"], new["id"]),
    )
    if new["updated_at"] > old["updated_at"]:
        # The newest device payload wins, under the older row's identity.
        metadata = rewrite_wallet_ids(json.loads(new["metadata"]), old["id"], target)
        conn.execute(
            """
            UPDATE transactions SET
                date = ?, amount = ?, currency = ?, payee = ?, status = ?,
                notes = ?, category = ?, metadata = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                new["date"], new["amount"], new["currency"], new["payee"],
                new["status"], new["notes"], new["category"],
                _dumps(metadata), new["updated_at"], old["id"],
            ),
        )
        conn.execute(
            "UPDATE canonical_transactions SET fingerprint = ? WHERE id = ?",
            (new["fingerprint"], old["id"]),
        )
    conn.execute("DELETE FROM transactions WHERE id = ?", (new["id"],))
    conn.execute("DELETE FROM canonical_transactions WHERE id = ?", (new["id"],))


def merge_accounts(
    conn: sqlite3.Connection,
    source: str,
    target: str,
    cutoff: str | None,
    loose: bool = False,
) -> dict[str, Any]:
    """Folds canonical account ``source`` into ``target`` inside ``conn``.

    For data that reached box before install IDs did, the only sign of which
    device sent a row is when box first saw it. Rows of ``source`` first seen
    at or after ``cutoff`` are the newer device's; rows of ``target`` first
    seen before it are the older device's. Identical fingerprints pair one to
    one in date order: the newer row's aliases move to the older row, which
    keeps its ID and first_seen_at, and the newer copy is deleted. Unpaired
    newer rows stay as they are (moved under ``target``); unpaired older rows
    are history only the old device had, and are kept.

    ``source == target`` de-duplicates one account across the cutoff.
    ``cutoff=None`` means "when box first saw any row of ``source``".
    ``loose`` adds a second pass that ignores the description (see below).
    """
    if cutoff is None:
        cutoff = conn.execute(
            "SELECT MIN(first_seen_at) FROM transactions WHERE account_id = ?", (source,)
        ).fetchone()[0] or _now()
    if source == target:
        newer = _rows(conn, "t.account_id = ? AND t.first_seen_at >= ?", (source, cutoff))
    else:
        newer = _rows(conn, "t.account_id = ?", (source,))
    older = _rows(conn, "t.account_id = ? AND t.first_seen_at < ?", (target, cutoff))

    newer_by: dict[str, list[dict[str, Any]]] = defaultdict(list)
    older_by: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in newer:
        newer_by[row["fingerprint"]].append(row)
    for row in older:
        older_by[row["fingerprint"]].append(row)

    matched: list[tuple[str, str]] = []
    unmatched: list[dict[str, Any]] = []
    ambiguous: list[dict[str, Any]] = []
    for fp, new_rows in newer_by.items():
        old_rows = older_by.get(fp, [])
        if old_rows and len(old_rows) != len(new_rows):
            ambiguous.append(
                {
                    "newer": [r["id"] for r in new_rows],
                    "older": [r["id"] for r in old_rows],
                    "date": new_rows[0]["date"],
                    "amount": new_rows[0]["amount"],
                    "payee": new_rows[0]["payee"],
                }
            )
        for new, old in zip(new_rows, old_rows):
            matched.append((new["id"], old["id"]))
            _fold(conn, new, old, target)
        unmatched.extend(new_rows[len(old_rows):])
    old_only = [r for fp, rows in older_by.items() for r in rows[len(newer_by.get(fp, [])):]]

    renamed: list[tuple[str, str]] = []
    if loose:
        # Apple sometimes rewrites a merchant's description between devices
        # ("SURI" -> "Suri"). Pair leftovers ignoring the description, but only
        # where the key is unique on both sides, so nothing is guessed.
        new_by: dict[tuple[str, ...], list[dict[str, Any]]] = defaultdict(list)
        old_by: dict[tuple[str, ...], list[dict[str, Any]]] = defaultdict(list)
        for row in unmatched:
            new_by[_loose_key(row)].append(row)
        for row in old_only:
            old_by[_loose_key(row)].append(row)
        for key, new_rows in new_by.items():
            old_rows = old_by.get(key, [])
            if len(new_rows) == 1 and len(old_rows) == 1:
                new, old = new_rows[0], old_rows[0]
                renamed.append((new["id"], old["id"]))
                _fold(conn, new, old, target)
                unmatched.remove(new)
                old_only.remove(old)

    if source != target:
        for row in unmatched:
            metadata = rewrite_wallet_ids(json.loads(row["metadata"]), row["id"], target)
            conn.execute(
                "UPDATE transactions SET account_id = ?, metadata = ? WHERE id = ?",
                (target, _dumps(metadata), row["id"]),
            )
            conn.execute(
                "UPDATE canonical_transactions SET account_id = ? WHERE id = ?",
                (target, row["id"]),
            )
        conn.execute(
            "UPDATE account_aliases SET canonical_account_id = ? WHERE canonical_account_id = ?",
            (target, source),
        )
        src = conn.execute("SELECT * FROM accounts WHERE id = ?", (source,)).fetchone()
        dst = conn.execute("SELECT * FROM accounts WHERE id = ?", (target,)).fetchone()
        if src is not None and (dst is None or src["updated_at"] > dst["updated_at"]):
            Database._write_account(conn, target, dict(src), src["updated_at"])
        conn.execute("DELETE FROM accounts WHERE id = ?", (source,))
        conn.execute("DELETE FROM canonical_accounts WHERE id = ?", (source,))

    return {
        "source": source,
        "target": target,
        "cutoff": cutoff,
        "matched": matched,
        "renamed": renamed,
        "unmatched": [
            {"id": r["id"], "date": r["date"], "amount": r["amount"], "payee": r["payee"]}
            for r in unmatched
        ],
        "old_only": [
            {"id": r["id"], "date": r["date"], "amount": r["amount"], "payee": r["payee"]}
            for r in old_only
        ],
        "ambiguous": ambiguous,
    }
