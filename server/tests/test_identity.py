"""Stable identity across devices: re-keyed uploads land on the rows box holds."""

from __future__ import annotations

import copy
import importlib.util
import json
import os
import sqlite3
import subprocess
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

os.environ.setdefault("FKS_TOKEN", "test-token")
os.environ.setdefault("FKS_DB_PATH", "/tmp/fks-test-unused.db")

from fastapi.testclient import TestClient  # noqa: E402

from app import cli, main, repair  # noqa: E402
from app.db import Database  # noqa: E402

AUTH = {"Authorization": "Bearer test-token"}
SERVER = Path(__file__).resolve().parents[1]

CARD, CASH, SAVINGS = "A99300BD-card", "0271CEE9-cash", "CC61535D-savings"


def wallet_txn(txn_id, account_id, account_name, when, value, desc, credit=False,
               kind="pointOfSale", original=None):
    amount = float(value) if credit else -float(value)
    return {
        "id": txn_id,
        "account_id": account_id,
        "date": when,
        "amount": amount,
        "currency": "USD",
        "payee": desc,
        "status": "posted",
        "notes": "booked",
        "category": "5814",
        "metadata": {
            "source": "financekit",
            "source_version": "1.0",
            "wallet": {
                "transaction_id": txn_id,
                "account_id": account_id,
                "account_display_name": account_name,
                "institution_name": "Apple",
                "transaction_date": when,
                "status": "booked",
                "transaction_type": kind,
                "credit_debit_indicator": "credit" if credit else "debit",
                "transaction_description": desc,
                "original_transaction_description": original or desc.upper(),
                "amount": {"value": value, "currency": "USD"},
            },
        },
    }


def history():
    """(account key, when, value, description, credit) for a small realistic history."""
    rows = []
    base = datetime(2019, 8, 1, 12, 0, tzinfo=timezone.utc)
    for i in range(12):
        when = (base + timedelta(days=30 * i)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        rows.append(("cash", when, f"{10 + i}.00", f"Apple Cash to Friend {i}", False))
        rows.append(("savings", when, f"{1 + i}.5", "Interest payment", True))
        rows.append(("card", when, f"{20 + i}.99", f"Merchant {i}", False))
    # A genuine repeat charge: same second, amount and merchant, twice.
    rows.append(("card", "2020-06-01T09:00:00.000Z", "4.50", "Coffee", False))
    rows.append(("card", "2020-06-01T09:00:00.000Z", "4.50", "Coffee", False))
    return rows


def packet(install, ids, rows, balances, names=None):
    names = names or {"card": "Apple Card", "cash": "Apple Cash", "savings": "Savings"}
    accounts = [
        {"id": ids[k], "name": names[k], "institution": "Apple", "balance": balances[k], "currency": "USD"}
        for k in ("card", "cash", "savings")
    ]
    txns = [
        wallet_txn(txn_id, ids[k], names[k], when, value, desc, credit)
        for txn_id, (k, when, value, desc, credit) in rows
    ]
    body = {"schema_version": 1, "accounts": accounts, "transactions": txns}
    if install:
        body["device_install_id"] = install
    return body


@pytest.fixture
def client(tmp_path, monkeypatch):
    database = Database(tmp_path / "fks.db")
    monkeypatch.setattr(main, "db", database)
    sent = []
    monkeypatch.setattr(main.notify, "send", lambda events: sent.append(events))
    c = TestClient(main.app)
    c.database = database
    c.notified = sent
    return c


def post(client, body):
    r = client.post("/financekit-sync", json=body, headers=AUTH)
    assert r.status_code == 200, r.text
    return r.json()


def snapshot(client):
    accounts = client.get("/accounts", headers=AUTH).json()["accounts"]
    txns = client.get("/transactions?limit=1000", headers=AUTH).json()["transactions"]
    return accounts, txns


def age_aliases(client, install, hours=48):
    then = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
    with sqlite3.connect(client.database.path) as conn:
        conn.execute(
            "UPDATE account_aliases SET last_seen_at = ? WHERE device_install_id = ?",
            (then, install),
        )


def first_device(client, install="install-A"):
    ids = {"card": CARD, "cash": CASH, "savings": SAVINGS}
    rows = [(str(uuid.uuid4()).upper(), r) for r in history()]
    post(client, packet(install, ids, rows, {"card": -100.0, "cash": 50.0, "savings": 1000.0}))
    return ids, rows


def strip(items, keys):
    return [{k: v for k, v in item.items() if k not in keys} for item in items]


def test_device_switch_is_invisible_to_consumers(client):
    _, rows = first_device(client)
    before_accounts, before_txns = snapshot(client)
    age_aliases(client, "install-A")

    # New phone: new account IDs for Cash and Savings, the same Card ID, fresh
    # transaction UUIDs for everything, and no Apple Cash before the cutoff.
    new_ids = {"card": CARD, "cash": "99B1EC23-new-cash", "savings": "373EA1D6-new-savings"}
    replay = [
        (str(uuid.uuid4()).upper(), r) for _, r in rows
        if not (r[0] == "cash" and r[1] < "2019-08-26")
    ]
    assert len(replay) == len(rows) - 1
    receipt = post(client, packet("install-B", new_ids, replay,
                                  {"card": -250.0, "cash": 75.0, "savings": 1200.0}))
    assert receipt["transactions_inserted"] == 0
    assert receipt["transactions_held"] == 0

    after_accounts, after_txns = snapshot(client)
    assert strip(after_accounts, {"updated_at", "balance"}) == strip(before_accounts, {"updated_at", "balance"})
    assert [a["balance"] for a in after_accounts] == [-250.0, 75.0, 1200.0]
    assert json.dumps(strip(after_txns, {"updated_at"})) == json.dumps(strip(before_txns, {"updated_at"}))
    assert any("recognised" in e for events in client.notified for e in events)

    # Replaying again changes nothing either.
    post(client, packet("install-B", new_ids, replay, {"card": -250.0, "cash": 75.0, "savings": 1200.0}))
    assert strip(snapshot(client)[1], {"updated_at"}) == strip(before_txns, {"updated_at"})


def test_original_description_is_not_part_of_the_fingerprint(client):
    _, rows = first_device(client)
    age_aliases(client, "install-A")
    new_ids = {"card": CARD, "cash": "99B1EC23", "savings": "373EA1D6"}
    body = packet("install-B", new_ids, [(str(uuid.uuid4()), r) for _, r in rows],
                  {"card": 0.0, "cash": 0.0, "savings": 0.0})
    for txn in body["transactions"]:
        txn["metadata"]["wallet"]["original_transaction_description"] = "SQ *SOMETHING ELSE"
    assert post(client, body)["transactions_inserted"] == 0
    _, txns = snapshot(client)
    assert len(txns) == len(rows)
    assert {t["metadata"]["wallet"]["original_transaction_description"] for t in txns} == {"SQ *SOMETHING ELSE"}
    assert all(t["metadata"]["wallet"]["transaction_id"] == t["id"] for t in txns)
    assert all(t["metadata"]["wallet"]["account_id"] == t["account_id"] for t in txns)


def test_repeat_charges_pair_one_to_one_and_a_surplus_is_new(client):
    first_device(client)
    age_aliases(client, "install-A")
    coffee = ("card", "2020-06-01T09:00:00.000Z", "4.50", "Coffee", False)
    ids = {"card": CARD, "cash": CASH, "savings": SAVINGS}
    body = packet("install-B", ids, [("B-1", coffee), ("B-2", coffee), ("B-3", coffee)],
                  {"card": 0.0, "cash": 0.0, "savings": 0.0})
    receipt = post(client, body)
    assert (receipt["transactions_updated"], receipt["transactions_inserted"]) == (2, 1)
    coffees = [t for t in snapshot(client)[1] if t["payee"] == "Coffee"]
    assert len(coffees) == 3 and "B-3" in {t["id"] for t in coffees}


def test_identical_row_from_the_same_install_is_always_new(client):
    first_device(client)
    ids = {"card": CARD, "cash": CASH, "savings": SAVINGS}
    again = ("card", "2019-08-01T12:00:00.000Z", "20.99", "Merchant 0", False)
    receipt = post(client, packet("install-A", ids, [("A-again", again)],
                                  {"card": 0.0, "cash": 0.0, "savings": 0.0}))
    assert receipt["transactions_inserted"] == 1


def test_pending_to_posted_updates_the_canonical_row(client):
    _, rows = first_device(client)
    age_aliases(client, "install-A")
    original_id, row = next((i, r) for i, r in rows if r[3] == "Merchant 5")
    pending = packet("install-B", {"card": CARD, "cash": CASH, "savings": SAVINGS},
                     [("B-m5", row)], {"card": 0.0, "cash": 0.0, "savings": 0.0})
    post(client, pending)
    posted = copy.deepcopy(pending)
    txn = posted["transactions"][0]
    txn["amount"] = -99.0
    txn["date"] = txn["metadata"]["wallet"]["transaction_date"] = "2020-01-30T00:00:00.000Z"
    txn["metadata"]["wallet"]["amount"]["value"] = "99.00"
    assert post(client, posted)["transactions_updated"] == 1
    match = [t for t in snapshot(client)[1] if t["id"] == original_id]
    assert match[0]["amount"] == -99.0
    assert not any(t["id"] == "B-m5" for t in snapshot(client)[1])


def test_live_account_is_held_until_aliased_by_hand(client, tmp_path):
    _, rows = first_device(client)
    # install-A synced moments ago, so a second Apple Cash is not a re-key.
    new_ids = {"card": CARD, "cash": "99B1EC23", "savings": SAVINGS}
    body = packet("install-B", new_ids,
                  [(str(uuid.uuid4()), r) for _, r in rows if r[0] == "cash"],
                  {"card": 0.0, "cash": 0.0, "savings": 0.0})
    receipt = post(client, body)
    assert receipt["transactions_held"] == 12
    accounts, txns = snapshot(client)
    assert {a["id"] for a in accounts} == {CARD, CASH, SAVINGS}
    assert len(txns) == len(rows)
    assert any("alias-account 99B1EC23" in e for events in client.notified for e in events)

    assert cli.main(["--db", str(client.database.path), "alias-account", "99B1EC23", CASH]) == 0
    accounts, txns = snapshot(client)
    assert {a["id"] for a in accounts} == {CARD, CASH, SAVINGS}
    assert len(txns) == len(rows)
    assert client.database.counts()["held_transactions"] == 0


def test_tripwire_holds_unmatched_history(client):
    first_device(client)
    age_aliases(client, "install-A")
    # Same Card ID, but old-dated rows box has never seen in this form.
    old = [(f"B-old-{i}", ("card", f"2019-09-0{i + 1}T10:00:00.000Z", "7.77", f"Unknown {i}", False))
           for i in range(4)]
    receipt = post(client, packet("install-B", {"card": CARD, "cash": CASH, "savings": SAVINGS},
                                  old, {"card": 0.0, "cash": 0.0, "savings": 0.0}))
    assert receipt["transactions_held"] == 4
    assert not any(t["payee"].startswith("Unknown") for t in snapshot(client)[1])
    assert any("Holding 4" in e for events in client.notified for e in events)

    db = client.database
    assert db.release_held(CARD) == 4
    assert sum(t["payee"].startswith("Unknown") for t in snapshot(client)[1]) == 4


def _old_database(path: Path):
    """The pre-identity storage module, from git, to build the broken state."""
    source = subprocess.run(["git", "show", "HEAD:server/app/db.py"], cwd=SERVER,
                            capture_output=True, text=True, check=True).stdout
    path.parent.mkdir(parents=True, exist_ok=True)
    module_path = path.parent / "old_db.py"
    module_path.write_text(source)
    spec = importlib.util.spec_from_file_location("old_db", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Database(path)


def test_repair_restores_original_identity(tmp_path, monkeypatch):
    path = tmp_path / "data" / "fks.db"
    old = _old_database(path)

    def write(ids, rows):
        body = packet(None, ids, rows, {"card": 1.0, "cash": 2.0, "savings": 3.0})
        old.upsert_packet(body["accounts"], body["transactions"])

    old_ids = {"card": CARD, "cash": CASH, "savings": SAVINGS}
    old_rows = [(str(uuid.uuid4()), r) for r in history()]
    write(old_ids, old_rows)
    with sqlite3.connect(path) as conn:
        conn.execute("UPDATE transactions SET first_seen_at = '2026-09-01T00:00:00+00:00'")
    new_ids = {"card": CARD, "cash": "99B1EC23-new-cash", "savings": "373EA1D6-new-savings"}
    new_rows = [(str(uuid.uuid4()), r) for _, r in old_rows if not (r[0] == "cash" and r[1] < "2019-08-26")]
    # Apple re-cased one merchant on the new phone.
    renamed = next(i for i, (_, r) in enumerate(new_rows) if r[3] == "Merchant 3")
    new_rows[renamed] = (new_rows[renamed][0], new_rows[renamed][1][:3] + ("MERCHANT 3",) + new_rows[renamed][1][4:])
    fresh = [("card-new-1", ("card", "2026-10-15T10:00:00.000Z", "12.00", "New Merchant", False))]
    write(new_ids, new_rows + fresh)
    assert len(old.list_transactions(limit=1000)) == len(old_rows) + len(new_rows) + 1  # the incident

    consumer_ids = {i for i, _ in old_rows}
    out = repair.run(path, apply=False, merges=[], switch_at=None, out=tmp_path / "dry")
    assert (out / "report.txt").exists() and (out / "fks-before-repair.db").exists()
    assert len(Database(path).list_transactions(limit=1000)) == len(old_rows) + len(new_rows) + 1

    repair.run(path, apply=True, merges=["99B1EC23:0271CEE9", "373EA1D6:CC61535D"],
               switch_at=None, out=tmp_path / "apply")
    db = Database(path)
    accounts = db.list_accounts()
    assert sorted(a["id"] for a in accounts) == sorted([CARD, CASH, SAVINGS])
    txns = db.list_transactions(limit=1000)
    ids = [t["id"] for t in txns]
    assert len(ids) == len(set(ids))
    assert consumer_ids | {"card-new-1"} == set(ids)
    keys = [(t["account_id"], t["date"], t["amount"], t["payee"]) for t in txns]
    coffee = ("A99300BD-card", "2020-06-01T09:00:00.000Z", -4.5, "Coffee")
    assert len(keys) - len(set(keys)) == 1 and keys.count(coffee) == 2  # the genuine repeat

    # The new phone, still on an old app build, keeps resolving to old IDs.
    body = packet(None, new_ids, new_rows, {"card": 9.0, "cash": 9.0, "savings": 9.0})
    result = db.upsert_packet(body["accounts"], body["transactions"])
    assert result["inserted"] == 0 and result["held"] == 0
    assert set(t["id"] for t in db.list_transactions(limit=1000)) == set(ids)
    assert len(db.list_accounts()) == 3


def test_unknown_balance_is_stored_as_null(client):
    ids, _ = first_device(client)
    body = packet("install-A", ids, [], {"card": -100.0, "cash": 50.0, "savings": 1000.0})
    del body["accounts"][0]["balance"]  # the app omits a credit account's balance
    post(client, body)
    accounts, _ = snapshot(client)
    assert {a["id"]: a["balance"] for a in accounts} == {
        ids["card"]: None, ids["cash"]: 50.0, ids["savings"]: 1000.0,
    }


def test_balance_not_null_is_dropped_from_older_databases(tmp_path):
    path = tmp_path / "old.db"
    with sqlite3.connect(path) as conn:
        conn.execute(
            """
            CREATE TABLE accounts (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, institution TEXT NOT NULL,
                balance REAL NOT NULL, currency TEXT NOT NULL, updated_at TEXT NOT NULL
            )
            """
        )
        conn.execute("INSERT INTO accounts VALUES ('a', 'Apple Card', 'Apple', 860.81, 'USD', 't')")
    Database(path)
    Database(path)  # a second open is a no-op
    with sqlite3.connect(path) as conn:
        notnull = {r[1]: r[3] for r in conn.execute("PRAGMA table_info(accounts)")}
        assert notnull["balance"] == 0
        assert conn.execute("SELECT * FROM accounts").fetchall() == [
            ("a", "Apple Card", "Apple", 860.81, "USD", "t")
        ]
