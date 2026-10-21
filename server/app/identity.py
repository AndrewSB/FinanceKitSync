"""Record identity across devices.

FinanceKit identifiers are device-local: a phone change or reinstall can hand
box the same real-world account or transaction under a new UUID. Box owns the
identity instead. A canonical ID is the first device ID box ever saw for a
record, and every later device ID is an alias of it.

This module holds the pure parts: name normalisation and the transaction
fingerprint used to recognise a re-keyed row. Nothing here touches SQLite.
"""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any

# Uploads from app builds that predate the install ID. Every device ID box held
# before identity tracking existed is aliased under this install.
LEGACY_INSTALL = "legacy"


def normalise_name(name: str) -> str:
    """Display names arrive as "Apple Cash"; compare them as "Apple Cash"."""
    return re.sub(r"\s+", " ", name.replace(" ", " ")).strip()


def _second(value: str) -> str:
    """An ISO-8601 timestamp, in UTC, to the second."""
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return value[:19]
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _decimal(value: Any) -> str:
    try:
        return format(Decimal(str(value)).normalize(), "f")
    except (InvalidOperation, ValueError):
        return str(value)


def fingerprint(txn: dict[str, Any]) -> str:
    """What makes two device rows the same real-world transaction.

    Wallet transaction date to the second, amount, currency, credit/debit,
    type and description. ``original_transaction_description`` is left out on
    purpose: it differs between devices for the same row.

    Rows without a wallet payload (test packets, foreign clients) fall back to
    the top-level date, amount, currency and payee.
    """
    wallet = (txn.get("metadata") or {}).get("wallet")
    if isinstance(wallet, dict) and "transaction_date" in wallet:
        amount = wallet.get("amount") or {}
        parts = [
            _second(wallet["transaction_date"]),
            _decimal(amount.get("value", "")),
            str(amount.get("currency", "")),
            str(wallet.get("credit_debit_indicator", "")),
            str(wallet.get("transaction_type", "")),
            str(wallet.get("transaction_description", "")),
        ]
    else:
        parts = [
            _second(txn["date"]),
            _decimal(txn["amount"]),
            txn["currency"],
            "",
            "",
            txn["payee"],
        ]
    return hashlib.sha256(json.dumps(parts).encode()).hexdigest()


def rewrite_wallet_ids(
    metadata: dict[str, Any], transaction_id: str, account_id: str
) -> dict[str, Any]:
    """The latest device payload, with its device IDs replaced by canonical ones."""
    wallet = metadata.get("wallet")
    if not isinstance(wallet, dict):
        return metadata
    return {
        **metadata,
        "wallet": {**wallet, "transaction_id": transaction_id, "account_id": account_id},
    }
