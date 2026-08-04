"""Push the App Store listing from tools/listing.json to App Store Connect.

Idempotent — safe to re-run. Edit listing.json, re-run, done. The point is that
the listing lives in version control instead of being retyped into a web form.

    export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=...
    python3 tools/push_listing.py            # show what would change
    python3 tools/push_listing.py --apply    # write it

The app record itself must already exist: the App Store Connect API refuses
`CREATE` on `apps` ("Allowed operations are: GET_COLLECTION, GET_INSTANCE,
UPDATE"), so that one step is manual. Everything after it is handled here.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc  # noqa: E402

APPLY = "--apply" in sys.argv
CONFIG = json.loads((Path(__file__).parent / "listing.json").read_text())


def log(action: str, detail: str = "") -> None:
    prefix = "  →" if APPLY else "  ·"
    print(f"{prefix} {action}{(' ' + detail) if detail else ''}")


def find_app() -> str:
    bundle_id = CONFIG["bundleId"]
    result = asc.get(f"/v1/apps?filter[bundleId]={bundle_id}")
    apps = result.get("data", [])
    if not apps:
        raise SystemExit(
            f"No App Store Connect record for {bundle_id}.\n\n"
            "The API cannot create one — apps only allows GET and UPDATE. Create it at\n"
            "https://appstoreconnect.apple.com → Apps → + → New App, using:\n\n"
            f"  Platform:   iOS\n"
            f"  Name:       {CONFIG['name']}\n"
            f"  Language:   English (U.S.)\n"
            f"  Bundle ID:  {bundle_id}\n"
            f"  SKU:        financekitsync-001\n\n"
            "Then re-run this script."
        )
    app = apps[0]
    print(f"app {app['id']} — {app['attributes']['name']}")
    return app["id"]


def sync_app_info(app_id: str) -> None:
    """Name, subtitle, privacy policy URL, and categories."""
    infos = asc.get(f"/v1/apps/{app_id}/appInfos")["data"]
    # The editable one is whichever isn't already live on the store.
    editable = next(
        (i for i in infos
         if i["attributes"].get("appStoreState") not in ("READY_FOR_SALE",)),
        infos[0],
    )
    info_id = editable["id"]

    # --- categories
    attrs = {}
    rels = {}
    if CONFIG.get("primaryCategory"):
        rels["primaryCategory"] = {
            "data": {"type": "appCategories", "id": CONFIG["primaryCategory"]}
        }
    if CONFIG.get("secondaryCategory"):
        rels["secondaryCategory"] = {
            "data": {"type": "appCategories", "id": CONFIG["secondaryCategory"]}
        }
    if rels:
        log("categories",
            f"{CONFIG.get('primaryCategory')} / {CONFIG.get('secondaryCategory')}")
        if APPLY:
            asc.patch(f"/v1/appInfos/{info_id}",
                      {"data": {"type": "appInfos", "id": info_id,
                                "attributes": attrs, "relationships": rels}})

    # --- localized name / subtitle / privacy policy
    locs = asc.get(f"/v1/appInfos/{info_id}/appInfoLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == CONFIG["locale"]), None)
    if loc is None:
        raise SystemExit(f"No {CONFIG['locale']} app info localization found")

    payload = {"name": CONFIG["name"], "subtitle": CONFIG["subtitle"]}
    # Empty strings would clear an existing value, so only send what's set.
    if CONFIG.get("privacyPolicyUrl"):
        payload["privacyPolicyUrl"] = CONFIG["privacyPolicyUrl"]
    else:
        log("privacyPolicyUrl", "SKIPPED — not set, and it is required to submit")

    log("name", repr(CONFIG["name"]))
    log("subtitle", repr(CONFIG["subtitle"]))
    if APPLY:
        asc.patch(f"/v1/appInfoLocalizations/{loc['id']}",
                  {"data": {"type": "appInfoLocalizations", "id": loc["id"],
                            "attributes": payload}})


def sync_version(app_id: str) -> None:
    """Description, keywords, promotional text, support/marketing URLs."""
    versions = asc.get(
        f"/v1/apps/{app_id}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION"
    )["data"]

    if versions:
        version_id = versions[0]["id"]
        print(f"version {versions[0]['attributes']['versionString']} (editable)")
    else:
        log("create version 1.0")
        if not APPLY:
            print("\n(dry run — stopping here; a version must exist to set description)")
            return
        created = asc.post("/v1/appStoreVersions", {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": "1.0"},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}}
                },
            }
        })
        version_id = created["data"]["id"]

    locs = asc.get(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"
    )["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == CONFIG["locale"]), None)
    if loc is None:
        raise SystemExit(f"No {CONFIG['locale']} version localization found")

    payload = {
        "description": CONFIG["description"],
        "keywords": CONFIG["keywords"],
        "promotionalText": CONFIG["promotionalText"],
    }

    # "What's New" only exists for updates. On a first release App Store Connect
    # rejects the whole PATCH with:
    #   409 STATE_ERROR — Attribute 'whatsNew' cannot be edited at this time
    # so include it only once something has actually shipped.
    released = asc.get(
        f"/v1/apps/{app_id}/appStoreVersions?filter[appStoreState]=READY_FOR_SALE&limit=1"
    )["data"]
    if released:
        payload["whatsNew"] = CONFIG["whatsNew"]
    else:
        log("whatsNew", "SKIPPED — not editable before a first release")
    for key in ("supportUrl", "marketingUrl"):
        if CONFIG.get(key):
            payload[key] = CONFIG[key]
        elif key == "supportUrl":
            log("supportUrl", "SKIPPED — not set, and it is required to submit")

    log("description", f"{len(CONFIG['description'])} chars")
    log("keywords", f"{len(CONFIG['keywords'])}/100 chars — {CONFIG['keywords']}")
    log("promotionalText", f"{len(CONFIG['promotionalText'])}/170 chars")
    if APPLY:
        asc.patch(f"/v1/appStoreVersionLocalizations/{loc['id']}",
                  {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                            "attributes": payload}})


def check_limits() -> None:
    """App Store Connect rejects these silently-late; catch them here instead."""
    problems = []
    if len(CONFIG["name"]) > 30:
        problems.append(f"name is {len(CONFIG['name'])} chars, limit 30")
    if len(CONFIG["subtitle"]) > 30:
        problems.append(f"subtitle is {len(CONFIG['subtitle'])} chars, limit 30")
    if len(CONFIG["keywords"]) > 100:
        problems.append(f"keywords are {len(CONFIG['keywords'])} chars, limit 100")
    if len(CONFIG["promotionalText"]) > 170:
        problems.append(f"promotionalText is {len(CONFIG['promotionalText'])} chars, limit 170")
    if len(CONFIG["description"]) > 4000:
        problems.append(f"description is {len(CONFIG['description'])} chars, limit 4000")
    if problems:
        raise SystemExit("Field limits exceeded:\n  " + "\n  ".join(problems))


if __name__ == "__main__":
    check_limits()
    if not APPLY:
        print("DRY RUN — pass --apply to write\n")
    app_id = find_app()
    sync_app_info(app_id)
    sync_version(app_id)
    print("\ndone" if APPLY else "\ndry run complete")
