"""One-time repair of the duplicates the 2026-10 phone switch left behind.

    python -m app.repair                 # dry run: report only
    python -m app.repair --apply         # back up, then repair

Both modes take a SQLite backup and write the report next to it, in
``<db dir>/repair-<stamp>/``. The dry run applies every change inside a
transaction and rolls it back, so its report is exactly what --apply would do.

By default it merges every pair of accounts that share an institution and
display name (newer into older: the new Apple Cash and Savings IDs onto the
old ones) and de-duplicates every other account across the switch (Apple Card,
which kept its account ID but re-keyed its transactions). Rows left over
after fingerprint matching are paired once more ignoring the description,
which Apple sometimes rewrites between devices, where that key is unique on
both sides. The switch is when
box first saw a row of a merged account; override with --switch-at.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .db import Database, merge_accounts
from .identity import normalise_name


class _DryRun(Exception):
    pass


def _resolve(conn: sqlite3.Connection, prefix: str) -> str:
    ids = [r[0] for r in conn.execute("SELECT id FROM accounts WHERE id LIKE ?", (prefix.rstrip(".") + "%",))]
    if len(ids) != 1:
        raise SystemExit(f"account prefix {prefix!r} matches {len(ids)} accounts")
    return ids[0]


def _plan(conn: sqlite3.Connection, merges: list[str]) -> list[tuple[str, str]]:
    if merges:
        pairs = []
        for spec in merges:
            new, _, old = spec.partition(":")
            pairs.append((_resolve(conn, new), _resolve(conn, old)))
        return pairs
    groups: dict[tuple[str, str], list[tuple[str, str]]] = defaultdict(list)
    for row in conn.execute(
        """
        SELECT a.id, a.name, a.institution,
               COALESCE((SELECT MIN(first_seen_at) FROM transactions t WHERE t.account_id = a.id), a.updated_at)
        FROM accounts a
        """
    ):
        groups[(row[2], normalise_name(row[1]))].append((row[3], row[0]))
    pairs = []
    for members in groups.values():
        members.sort()
        oldest = members[0][1]
        pairs.extend((account, oldest) for _, account in members[1:])
    return pairs


def _duplicates(conn: sqlite3.Connection) -> list[dict[str, Any]]:
    return [
        dict(r)
        for r in conn.execute(
            """
            SELECT account_id, date, amount, payee, COUNT(*) AS n, GROUP_CONCAT(id) AS ids
            FROM transactions GROUP BY account_id, date, amount, payee HAVING n > 1
            """
        )
    ]


def run(db_path: Path, apply: bool, merges: list[str], switch_at: str | None, out: Path | None) -> Path:
    db = Database(db_path)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = out or db_path.parent / f"repair-{stamp}"
    out.mkdir(parents=True, exist_ok=True)

    backup = out / f"{db_path.stem}-before-repair.db"
    with sqlite3.connect(db_path) as src, sqlite3.connect(backup) as dst:
        src.backup(dst)

    report: dict[str, Any] = {"mode": "apply" if apply else "dry-run", "backup": str(backup)}
    try:
        with db.transaction() as conn:
            pairs = _plan(conn, merges)
            cutoff = switch_at or conn.execute(
                f"""
                SELECT MIN(first_seen_at) FROM transactions
                WHERE account_id IN ({",".join("?" * len(pairs))})
                """,
                [new for new, _ in pairs],
            ).fetchone()[0]
            if cutoff is None:
                raise SystemExit("no merge pairs found; pass --switch-at to de-duplicate")
            report["switch_at"] = cutoff
            report["duplicates_before"] = len(_duplicates(conn))
            merged = {account for pair in pairs for account in pair}
            others = [r[0] for r in conn.execute("SELECT id FROM accounts") if r[0] not in merged]
            results = [merge_accounts(conn, new, old, cutoff, loose=True) for new, old in pairs]
            results += [merge_accounts(conn, account, account, cutoff, loose=True) for account in others]
            report["accounts"] = results
            report["accounts_after"] = [dict(r) for r in conn.execute("SELECT id, name, institution FROM accounts")]
            report["duplicates_after"] = _duplicates(conn)
            if not apply:
                raise _DryRun
    except _DryRun:
        pass

    (out / "report.json").write_text(json.dumps(report, indent=2))
    lines = [f"{report['mode']} — switch at {report['switch_at']}", f"backup: {backup}", ""]
    for r in report["accounts"]:
        title = r["target"] if r["source"] == r["target"] else f"{r['source']} -> {r['target']}"
        lines.append(
            f"{title}: {len(r['matched'])} matched + {len(r['renamed'])} renamed (duplicates dropped), "
            f"{len(r['unmatched'])} unmatched newer (kept), {len(r['old_only'])} old-only (kept), "
            f"{len(r['ambiguous'])} ambiguous group(s)"
        )
        for group in r["ambiguous"]:
            lines.append(
                f"    ambiguous {group['date']} {group['amount']} {group['payee']}: "
                f"{len(group['newer'])} newer vs {len(group['older'])} older"
            )
        for row in r["unmatched"]:
            lines.append(f"    unmatched {row['date']} {row['amount']} {row['payee']} ({row['id']})")
    lines.append("")
    lines.append(f"accounts after: {', '.join(a['name'] + ' ' + a['id'] for a in report['accounts_after'])}")
    lines.append(
        f"(date, amount, payee, account) duplicates: {report['duplicates_before']} before, "
        f"{len(report['duplicates_after'])} after"
    )
    for d in report["duplicates_after"]:
        lines.append(f"    {d['date']} {d['amount']} {d['payee']} x{d['n']}: {d['ids']}")
    (out / "report.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nreport: {out / 'report.txt'}")
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.repair")
    parser.add_argument("--db", default=os.environ.get("FKS_DB_PATH", "/data/financekitsync.db"))
    parser.add_argument("--apply", action="store_true", help="Write the repair (default: dry run)")
    parser.add_argument(
        "--merge", action="append", default=[], metavar="NEW:OLD",
        help="Account ID prefixes to merge, newer into older (default: same name and institution)",
    )
    parser.add_argument("--switch-at", help="ISO-8601 time the new device first uploaded")
    parser.add_argument("--out", type=Path, help="Report and backup directory")
    args = parser.parse_args(argv)
    run(Path(args.db), args.apply, args.merge, args.switch_at, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
