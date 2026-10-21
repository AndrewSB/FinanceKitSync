"""Identity tripwire notifications, through Box API's ``/notify`` relay.

Best effort: the upload that raised the event has already committed, so a
relay failure is logged and never fails the sync.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import urllib.error
import urllib.request

logger = logging.getLogger("financekitsync")


def send(events: list[str]) -> None:
    message = "\n\n".join(events)
    for event in events:
        logger.warning("identity: %s", event)

    url = os.environ.get("FKS_NOTIFY_URL", "").strip()
    key = os.environ.get("FKS_NOTIFY_API_KEY", "").strip()
    if not url or not key:
        logger.warning("FKS_NOTIFY_URL / FKS_NOTIFY_API_KEY unset; not notifying")
        return

    request = urllib.request.Request(
        url,
        data=json.dumps({"title": "FinanceKitSync", "message": message[:4000]}).encode(),
        headers={
            "Content-Type": "application/json",
            "X-API-Key": key,
            # The relay replays a cached answer for a repeated request ID, so
            # the same events never notify twice.
            "X-Request-ID": hashlib.sha256(message.encode()).hexdigest()[:32],
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            response.read()
    except (urllib.error.URLError, TimeoutError) as exc:
        logger.error("notify relay failed: %s", exc)
