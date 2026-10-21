"""Manual identity resolution: ``financekit <command>``.

    financekit pending
    financekit alias-account <device_account_id> <canonical_account_id>
    financekit release-held <device_account_id> [--drop]

Runs against FKS_DB_PATH directly; ``server/financekit`` wraps it in the
running container.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from .db import Database, IdentityError


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="financekit")
    parser.add_argument("--db", default=os.environ.get("FKS_DB_PATH", "/data/financekitsync.db"))
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("pending", help="List held accounts and transactions")
    alias = commands.add_parser(
        "alias-account", help="Resolve a device account onto a canonical account"
    )
    alias.add_argument("device_account_id")
    alias.add_argument("canonical_account_id")
    release = commands.add_parser(
        "release-held", help="Accept tripwire-held transactions as new rows"
    )
    release.add_argument("device_account_id")
    release.add_argument("--drop", action="store_true", help="Discard them instead")
    commands.add_parser("held", help="Alias of pending")
    args = parser.parse_args(argv)

    db = Database(Path(args.db))
    try:
        if args.command in ("pending", "held"):
            result = db.list_pending()
        elif args.command == "alias-account":
            result = db.alias_account(args.device_account_id, args.canonical_account_id)
        else:
            result = {"released" if not args.drop else "dropped": db.release_held(
                args.device_account_id, drop=args.drop
            )}
    except IdentityError as exc:
        print(f"financekit: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
