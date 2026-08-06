"""Minimal App Store Connect API client.

Signs its own ES256 JWT with `cryptography` rather than pulling in PyJWT, which
has no wheel for the Python 3.14 on this machine.

Credentials come from the environment, never from source:

    export ASC_KEY_ID=...
    export ASC_ISSUER_ID=...
    export ASC_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8

Usage:
    python3 tools/asc.py whoami
    python3 tools/asc.py get /v1/apps
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from base64 import urlsafe_b64encode
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

BASE = "https://api.appstoreconnect.apple.com"


def _b64(data: bytes) -> bytes:
    return urlsafe_b64encode(data).rstrip(b"=")


def make_token() -> str:
    key_id = os.environ["ASC_KEY_ID"]
    issuer_id = os.environ["ASC_ISSUER_ID"]
    key_path = Path(os.environ["ASC_KEY_PATH"]).expanduser()

    private_key = serialization.load_pem_private_key(
        key_path.read_bytes(), password=None
    )

    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": now,
        # Apple rejects anything beyond 20 minutes.
        "exp": now + 15 * 60,
        "aud": "appstoreconnect-v1",
    }

    signing_input = (
        _b64(json.dumps(header, separators=(",", ":")).encode())
        + b"."
        + _b64(json.dumps(payload, separators=(",", ":")).encode())
    )

    der = private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    # JWS wants the raw r||s pair, not the DER structure OpenSSL produces.
    r, s = utils.decode_dss_signature(der)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")

    return (signing_input + b"." + _b64(raw)).decode()


def request(method: str, path: str, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {make_token()}")
    if data is not None:
        req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        try:
            detail = json.dumps(json.loads(detail), indent=2)
        except Exception:
            pass
        raise SystemExit(f"HTTP {exc.code} {method} {url}\n{detail}") from None


def get(path: str) -> dict:
    return request("GET", path)


def patch(path: str, body: dict) -> dict:
    return request("PATCH", path, body)


def post(path: str, body: dict) -> dict:
    return request("POST", path, body)


def delete(path: str) -> dict:
    return request("DELETE", path)


def upload(operation: dict, chunk: bytes) -> None:
    """Perform one of the `uploadOperations` Apple hands back when you reserve
    an asset (a screenshot, an app preview).

    Deliberately not routed through `request`: these go to Apple's asset
    storage, not the API, and must be sent *without* the bearer token — with
    only the headers named in the operation, and a raw body rather than JSON.
    """
    req = urllib.request.Request(
        operation["url"], data=chunk, method=operation["method"]
    )
    for header in operation.get("requestHeaders", []):
        req.add_header(header["name"], header["value"])

    try:
        with urllib.request.urlopen(req) as response:
            response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise SystemExit(
            f"HTTP {exc.code} {operation['method']} {operation['url']}\n{detail}"
        ) from None


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)

    command = sys.argv[1]
    if command == "whoami":
        # Cheapest authenticated call that proves the key, issuer, and role.
        result = get("/v1/apps?limit=200")
        apps = result.get("data", [])
        print(f"authenticated — {len(apps)} app(s) visible")
        for app in apps:
            attrs = app["attributes"]
            print(f"  {app['id']}  {attrs.get('bundleId'):40}  {attrs.get('name')}")
    elif command == "get":
        print(json.dumps(get(sys.argv[2]), indent=2))
    else:
        raise SystemExit(f"unknown command: {command}")
