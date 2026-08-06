"""Upload the App Store screenshots produced by tools/screenshots.sh.

Idempotent — safe to re-run. Each display size's set is emptied and refilled,
so the order on the listing always matches the filenames on disk.

    ./tools/screenshots.sh                       # capture
    export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=...
    python3 tools/push_screenshots.py            # show what would change
    python3 tools/push_screenshots.py --apply    # upload

Uploading an asset to App Store Connect is four steps, not one:

  1. POST /v1/appScreenshots reserves a slot and returns `uploadOperations`
  2. PUT each operation's byte range to Apple's asset storage
  3. PATCH the screenshot with `uploaded: true` and an MD5 of the file
  4. Apple processes it asynchronously; `assetDeliveryState` reports the result

Step 4 is why this script polls at the end. A screenshot that uploads fine can
still fail processing — usually for being the wrong pixel size — and until it
reaches COMPLETE it does not count toward the version's requirements.
"""

from __future__ import annotations

import hashlib
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc  # noqa: E402

APPLY = "--apply" in sys.argv
ROOT = Path(__file__).parent.parent
CONFIG = json.loads((Path(__file__).parent / "listing.json").read_text())

# Directory name under build/screenshots → App Store Connect display type.
# These two are what App Store Connect requires for an iPhone-only app.
#
# Note the mismatch on the first one: the web UI calls that slot "iPhone 6.9"
# Display" but the API identifier is still APP_IPHONE_67, from back when 6.7"
# was the largest iPhone. There is no APP_IPHONE_69 — the API rejects it — and
# the slot accepts 1320x2868 (6.9") as well as 1290x2796 (6.7").
SIZES = {
    "6.9in": "APP_IPHONE_67",
    "6.5in": "APP_IPHONE_65",
}

# Apple's docs put the limit at 16 MB per part; screenshots are far smaller
# than this, so in practice every upload is a single operation.
LOCALE = "en-US"


def log(action: str, detail: str = "") -> None:
    prefix = "  →" if APPLY else "  ·"
    print(f"{prefix} {action}{(' ' + detail) if detail else ''}")


def editable_localization() -> str:
    """The en-US localization of the version that isn't already on the store."""
    apps = asc.get(f"/v1/apps?filter[bundleId]={CONFIG['bundleId']}")["data"]
    if not apps:
        raise SystemExit(f"No App Store Connect record for {CONFIG['bundleId']}.")
    app_id = apps[0]["id"]

    versions = asc.get(f"/v1/apps/{app_id}/appStoreVersions?limit=10")["data"]
    editable = next(
        (v for v in versions
         if v["attributes"].get("appStoreState") != "READY_FOR_SALE"),
        None,
    )
    if editable is None:
        raise SystemExit("No editable version — every version is already live.")
    print(f"app {app_id} — version {editable['attributes']['versionString']} "
          f"({editable['attributes']['appStoreState']})")

    locs = asc.get(
        f"/v1/appStoreVersions/{editable['id']}/appStoreVersionLocalizations"
    )["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if loc is None:
        raise SystemExit(f"No {LOCALE} localization on that version.")
    return loc["id"]


def screenshot_set(localization_id: str, display_type: str) -> str | None:
    """The existing set for this display size, or a new one. None in dry-run."""
    sets = asc.get(
        f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
    )["data"]
    existing = next(
        (s for s in sets
         if s["attributes"]["screenshotDisplayType"] == display_type),
        None,
    )
    if existing:
        return existing["id"]

    log("create screenshot set", display_type)
    if not APPLY:
        return None
    created = asc.post("/v1/appScreenshotSets", {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": localization_id,
                    }
                }
            },
        }
    })
    return created["data"]["id"]


def clear(set_id: str) -> None:
    """Removes what's there so a re-run can't append duplicates or leave the
    listing in a half-updated order."""
    for shot in asc.get(f"/v1/appScreenshotSets/{set_id}/appScreenshots")["data"]:
        log("delete existing", shot["attributes"].get("fileName", shot["id"]))
        if APPLY:
            asc.delete(f"/v1/appScreenshots/{shot['id']}")


def upload_one(set_id: str, path: Path) -> str:
    data = path.read_bytes()

    reserved = asc.post("/v1/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileSize": len(data), "fileName": path.name},
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}
                }
            },
        }
    })
    shot_id = reserved["data"]["id"]

    for operation in reserved["data"]["attributes"]["uploadOperations"]:
        offset = operation["offset"]
        asc.upload(operation, data[offset:offset + operation["length"]])

    # Apple verifies this against what it received; a mismatch fails processing
    # rather than silently storing a corrupt image.
    asc.patch(f"/v1/appScreenshots/{shot_id}", {
        "data": {
            "type": "appScreenshots",
            "id": shot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": hashlib.md5(data).hexdigest(),
            },
        }
    })
    return shot_id


def await_processing(shot_ids: list[str]) -> bool:
    """Polls until every screenshot lands. Returns whether all of them passed."""
    print("\nwaiting for Apple to process the uploads…")
    pending = dict.fromkeys(shot_ids)
    deadline = time.monotonic() + 300

    while pending and time.monotonic() < deadline:
        time.sleep(5)
        for shot_id in list(pending):
            attrs = asc.get(f"/v1/appScreenshots/{shot_id}")["data"]["attributes"]
            state = (attrs.get("assetDeliveryState") or {}).get("state")
            if state in ("COMPLETE", "FAILED"):
                pending.pop(shot_id)
                name = attrs.get("fileName", shot_id)
                if state == "COMPLETE":
                    print(f"  ✓ {name}")
                else:
                    errors = (attrs.get("assetDeliveryState") or {}).get("errors")
                    print(f"  ✗ {name} — {errors}")

    for shot_id in pending:
        print(f"  ? {shot_id} — still processing after 5 minutes")
    return not pending


def main() -> None:
    if not APPLY:
        print("dry run — pass --apply to upload\n")

    localization_id = editable_localization()
    uploaded: list[str] = []

    for directory, display_type in SIZES.items():
        source = ROOT / "build" / "screenshots" / directory
        images = sorted(source.glob("*.png"))
        if not images:
            raise SystemExit(
                f"No screenshots in {source}. Run ./tools/screenshots.sh first."
            )

        print(f"\n{directory} → {display_type}  ({len(images)} images)")
        set_id = screenshot_set(localization_id, display_type)
        if set_id:
            clear(set_id)

        for image in images:
            log("upload", f"{image.name} ({image.stat().st_size // 1024} KB)")
            if APPLY and set_id:
                uploaded.append(upload_one(set_id, image))

    if APPLY and uploaded:
        if not await_processing(uploaded):
            raise SystemExit("Some screenshots did not finish processing.")


if __name__ == "__main__":
    main()
