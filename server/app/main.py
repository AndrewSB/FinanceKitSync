"""FinanceKitSync sync server.

Accepts transaction packets from the FinanceKitSync iOS app and stores them in
SQLite. Single user, single bearer token — this is a personal server, not a
multi-tenant service.

Replaces the throwaway server that lived in LunchSync/server/main.py. Changes:
bearer auth (v0 accepted any caller that could reach the port), SQLite upsert
instead of unbounded JSONL append, and a response body that reports what
actually landed.
"""

from __future__ import annotations

import hmac
import logging
import os
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from pydantic import BaseModel, Field

from .db import Database

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
)
logger = logging.getLogger("financekitsync")

SCHEMA_VERSION = 1

DB_PATH = Path(os.environ.get("FKS_DB_PATH", "/data/financekitsync.db"))
TOKEN = os.environ.get("FKS_TOKEN", "")

if not TOKEN:
    # Refuse to start rather than silently accepting every request — the whole
    # point of v1 over v0 is that this endpoint is authenticated.
    raise RuntimeError("FKS_TOKEN is not set; refusing to start unauthenticated")

db = Database(DB_PATH)

app = FastAPI(
    title="FinanceKitSync",
    version="1.0.0",
    # No interactive docs: this is a single-purpose endpoint on the public
    # internet, and /docs would advertise it to anyone who finds the host.
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)


# -- auth ---------------------------------------------------------------


def require_token(
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    presented = authorization.removeprefix("Bearer ").strip()
    # compare_digest, not ==, so a wrong token can't be recovered by timing.
    if not hmac.compare_digest(presented, TOKEN):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )


Authenticated = Annotated[None, Depends(require_token)]


# -- schema -------------------------------------------------------------


class Account(BaseModel):
    id: str
    name: str
    institution: str
    balance: float
    currency: str


class Transaction(BaseModel):
    id: str
    account_id: str
    date: str
    amount: float
    currency: str
    payee: str
    status: str
    notes: str
    category: str
    # Free-form FinanceKit capture. Stored as-is so a client that learns new
    # fields doesn't need a server deploy to start sending them.
    metadata: dict[str, Any] = Field(default_factory=dict)


class Packet(BaseModel):
    schema_version: int
    accounts: list[Account] = Field(default_factory=list)
    transactions: list[Transaction] = Field(default_factory=list)


class Receipt(BaseModel):
    accounts_received: int
    transactions_received: int
    transactions_inserted: int
    transactions_updated: int


# -- routes -------------------------------------------------------------


@app.get("/health")
def health() -> dict[str, Any]:
    """Unauthenticated on purpose: onboarding checks reachability before a
    token has been entered. Returns nothing an unauthenticated scanner could
    use — no counts, no hostname, no version of anything but the wire schema.
    """
    return {"status": "ok", "schema_version": SCHEMA_VERSION}


@app.post("/financekit-sync", response_model=Receipt)
def financekit_sync(packet: Packet, _: Authenticated) -> Receipt:
    if packet.schema_version != SCHEMA_VERSION:
        # Reject rather than guess. A client sending a schema we don't
        # understand is better off retrying after the server is updated.
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Unsupported schema_version {packet.schema_version}; "
                f"this server speaks {SCHEMA_VERSION}"
            ),
        )

    result = db.upsert_packet(
        accounts=[a.model_dump() for a in packet.accounts],
        transactions=[t.model_dump() for t in packet.transactions],
    )

    logger.info(
        "packet: %d account(s), %d transaction(s) (%d new, %d updated)",
        len(packet.accounts),
        len(packet.transactions),
        result["inserted"],
        result["updated"],
    )

    return Receipt(
        accounts_received=len(packet.accounts),
        transactions_received=len(packet.transactions),
        transactions_inserted=result["inserted"],
        transactions_updated=result["updated"],
    )


@app.get("/accounts")
def accounts(_: Authenticated) -> dict[str, Any]:
    return {"accounts": db.list_accounts()}


@app.get("/transactions")
def transactions(
    _: Authenticated,
    since: Annotated[str | None, Query(description="ISO-8601 lower bound on date")] = None,
    limit: Annotated[int, Query(ge=1, le=1000)] = 100,
) -> dict[str, Any]:
    return {"transactions": db.list_transactions(since=since, limit=limit)}


@app.get("/stats")
def stats(_: Authenticated) -> dict[str, Any]:
    return db.counts()
