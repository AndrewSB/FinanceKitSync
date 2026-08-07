# Archive

Superseded material, kept for provenance. Nothing here describes the current
state of the project — see [`../STATUS.md`](../STATUS.md) for that.

## `entitlement-request-text.md`

The drafts written for the FinanceKit entitlement request, filed 2026-08-04 as
`453VPT726K` and approved 2026-08-06. Archived because the request is granted
and cannot be re-filed. Worth reading for one reason: both drafts name the
Info.plist key as `NSFinancialDataDescription`, which does not exist — the
earliest appearance of the typo that later shipped in build 19.

## `v0-server-main.cpython-314.pyc`

The only surviving artifact of the original mirror server.

It lived at `LunchSync/server/main.py`, was never committed, and the source file
no longer exists — by the time this project started, `LunchSync/server/`
contained nothing but this one compiled file. The v1 wire contract in
[`../SPEC.md`](../SPEC.md) §5 was reconstructed from its bytecode.

Kept purely for provenance. Nothing depends on it, and the current server is a
rewrite rather than a port. To inspect it:

```python
import dis, marshal
with open("v0-server-main.cpython-314.pyc", "rb") as f:
    f.read(16)                    # skip the header
    dis.dis(marshal.load(f))
```

What it did: `GET /health`, `POST /finance-kit-sync`, Pydantic models for
`MirrorPacket` / `MirrorAccount` / `MirrorTransaction`, and an append to
`received_packets.jsonl`. No authentication of any kind.
