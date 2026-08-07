"""Push the auto-renewable subscription from tools/subscription.json to App
Store Connect: group, product, price, localization, free trial, availability,
and the review screenshot.

Same shape as push_listing.py — the product lives in version control instead of
being retyped into a web form. Idempotent; dry-run by default.

    export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=...
    python3 tools/push_subscription.py            # show what would change
    python3 tools/push_subscription.py --apply    # write it

What this does not do:

  * Agree to the Paid Applications agreement. Until that is signed in App Store
    Connect, every in-app purchase endpoint 403s and nothing below will work.
  * Submit the subscription for review. It is submitted with the app version.
  * Set the Terms of Use (EULA) link. Apple's standard EULA applies by default
    and the paywall links to it; overriding it is an app-level field.

The review screenshot is required — a subscription with no screenshot sits in
"Missing Metadata" and blocks the version it ships with. Capture it first:

    ./tools/screenshots.sh     # writes build/screenshots/6.9in/6-paywall.png
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc  # noqa: E402

APPLY = "--apply" in sys.argv
ROOT = Path(__file__).parent.parent
CONFIG = json.loads((Path(__file__).parent / "subscription.json").read_text())


def log(action: str, detail: str = "") -> None:
    prefix = "  →" if APPLY else "  ·"
    print(f"{prefix} {action}{(' ' + detail) if detail else ''}")


def find_app() -> str:
    result = asc.get(f"/v1/apps?filter[bundleId]={CONFIG['bundleId']}")
    apps = result.get("data", [])
    if not apps:
        raise SystemExit(
            f"No App Store Connect record for {CONFIG['bundleId']}. "
            "Run push_listing.py first — it explains how."
        )
    app = apps[0]
    print(f"app {app['id']} — {app['attributes']['name']}")
    return app["id"]


# --- group -----------------------------------------------------------------


def subscription_group(app_id: str) -> str | None:
    """The group exists so users can move between tiers. There is one tier
    today, but a subscription cannot exist outside a group."""
    name = CONFIG["groupReferenceName"]
    existing = asc.get(f"/v1/apps/{app_id}/subscriptionGroups?limit=200")["data"]
    for group in existing:
        if group["attributes"]["referenceName"] == name:
            print(f"group {group['id']} — {name}")
            return group["id"]

    log("create subscription group", name)
    if not APPLY:
        return None

    group = asc.post(
        "/v1/subscriptionGroups",
        {
            "data": {
                "type": "subscriptionGroups",
                "attributes": {"referenceName": name},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )["data"]
    print(f"group {group['id']} — {name}")
    return group["id"]


def group_localization(group_id: str) -> None:
    """The name users see in Settings → Subscriptions."""
    locale = CONFIG["locale"]
    existing = asc.get(
        f"/v1/subscriptionGroups/{group_id}/subscriptionGroupLocalizations?limit=200"
    )["data"]
    match = next(
        (loc for loc in existing if loc["attributes"]["locale"] == locale), None
    )
    attrs = {"name": CONFIG["groupDisplayName"], "locale": locale}

    if match:
        if match["attributes"].get("name") == attrs["name"]:
            return
        log("update group name", attrs["name"])
        if APPLY:
            asc.patch(
                f"/v1/subscriptionGroupLocalizations/{match['id']}",
                {
                    "data": {
                        "type": "subscriptionGroupLocalizations",
                        "id": match["id"],
                        "attributes": {"name": attrs["name"]},
                    }
                },
            )
        return

    log("create group localization", locale)
    if APPLY:
        asc.post(
            "/v1/subscriptionGroupLocalizations",
            {
                "data": {
                    "type": "subscriptionGroupLocalizations",
                    "attributes": attrs,
                    "relationships": {
                        "subscriptionGroup": {
                            "data": {"type": "subscriptionGroups", "id": group_id}
                        }
                    },
                }
            },
        )


# --- the subscription itself ----------------------------------------------


def subscription(group_id: str) -> str | None:
    product_id = CONFIG["productId"]
    existing = asc.get(
        f"/v1/subscriptionGroups/{group_id}/subscriptions?limit=200"
    )["data"]
    for sub in existing:
        if sub["attributes"]["productId"] == product_id:
            print(f"subscription {sub['id']} — {product_id} "
                  f"({sub['attributes'].get('state')})")
            return sub["id"]

    log("create subscription", f"{product_id} {CONFIG['subscriptionPeriod']}")
    if not APPLY:
        return None

    sub = asc.post(
        "/v1/subscriptions",
        {
            "data": {
                "type": "subscriptions",
                "attributes": {
                    "name": CONFIG["referenceName"],
                    "productId": product_id,
                    "subscriptionPeriod": CONFIG["subscriptionPeriod"],
                    "familySharable": False,
                    "reviewNote": CONFIG["reviewNote"],
                    # One tier, so level 1. Levels only matter for upgrade and
                    # downgrade paths within a group.
                    "groupLevel": 1,
                },
                "relationships": {
                    "group": {"data": {"type": "subscriptionGroups", "id": group_id}}
                },
            }
        },
    )["data"]
    print(f"subscription {sub['id']} — {product_id}")
    return sub["id"]


def localization(sub_id: str) -> None:
    """Display name and description — required, and a common cause of
    'Missing Metadata'."""
    locale = CONFIG["locale"]
    existing = asc.get(
        f"/v1/subscriptions/{sub_id}/subscriptionLocalizations?limit=200"
    )["data"]
    attrs = {
        "name": CONFIG["displayName"],
        "description": CONFIG["description"],
        "locale": locale,
    }
    match = next(
        (loc for loc in existing if loc["attributes"]["locale"] == locale), None
    )

    if match:
        current = match["attributes"]
        if all(current.get(k) == v for k, v in attrs.items()):
            return
        log("update localization", locale)
        if APPLY:
            asc.patch(
                f"/v1/subscriptionLocalizations/{match['id']}",
                {
                    "data": {
                        "type": "subscriptionLocalizations",
                        "id": match["id"],
                        "attributes": {
                            "name": attrs["name"],
                            "description": attrs["description"],
                        },
                    }
                },
            )
        return

    log("create localization", f"{locale} — {attrs['name']}")
    if APPLY:
        asc.post(
            "/v1/subscriptionLocalizations",
            {
                "data": {
                    "type": "subscriptionLocalizations",
                    "attributes": attrs,
                    "relationships": {
                        "subscription": {
                            "data": {"type": "subscriptions", "id": sub_id}
                        }
                    },
                }
            },
        )


def price(sub_id: str) -> None:
    """Prices are chosen from Apple's price points, not typed as numbers: pick
    the USA point whose customer price matches, and Apple derives every other
    territory from it."""
    current = asc.get(
        f"/v1/subscriptions/{sub_id}/prices"
        "?include=subscriptionPricePoint&filter[territory]=USA&limit=200"
    )
    for point in current.get("included", []):
        if point["attributes"]["customerPrice"] == CONFIG["priceUsd"]:
            print(f"price ${CONFIG['priceUsd']}/USA — already set")
            return

    points = asc.get(
        f"/v1/subscriptions/{sub_id}/pricePoints?filter[territory]=USA&limit=8000"
    )["data"]
    match = next(
        (p for p in points if p["attributes"]["customerPrice"] == CONFIG["priceUsd"]),
        None,
    )
    if not match:
        raise SystemExit(
            f"No USA price point at {CONFIG['priceUsd']}. Apple's ladder is fixed; "
            "pick a price it actually offers."
        )

    log("set price", f"${CONFIG['priceUsd']} USA base, all territories")
    if APPLY:
        asc.post(
            "/v1/subscriptionPrices",
            {
                "data": {
                    "type": "subscriptionPrices",
                    "attributes": {"preserveCurrentPrice": False},
                    "relationships": {
                        "subscription": {
                            "data": {"type": "subscriptions", "id": sub_id}
                        },
                        "subscriptionPricePoint": {
                            "data": {
                                "type": "subscriptionPricePoints",
                                "id": match["id"],
                            }
                        },
                    },
                }
            },
        )


def availability(sub_id: str) -> None:
    """All territories, including ones Apple adds later."""
    existing = asc.get(f"/v1/subscriptions/{sub_id}/subscriptionAvailability")
    if existing.get("data"):
        print("availability — already set")
        return

    log("availability", "all territories, including future ones")
    if APPLY:
        territories = asc.get("/v1/territories?limit=200")["data"]
        asc.post(
            "/v1/subscriptionAvailabilities",
            {
                "data": {
                    "type": "subscriptionAvailabilities",
                    "attributes": {"availableInNewTerritories": True},
                    "relationships": {
                        "subscription": {
                            "data": {"type": "subscriptions", "id": sub_id}
                        },
                        "availableTerritories": {
                            "data": [
                                {"type": "territories", "id": t["id"]}
                                for t in territories
                            ]
                        },
                    },
                }
            },
        )


def introductory_offer(sub_id: str) -> None:
    """The free trial.

    This is what makes the trial automatic: StoreKit applies it at purchase for
    anyone eligible, with no code branching in the app. Eligibility is Apple's
    to decide — a user who has already had it on this Apple ID will not get it
    again, which is why the paywall reads the offer back off StoreKit rather
    than hardcoding "3 days".

    No territory relationship: omitting it means every territory.
    """
    offer = CONFIG["introductoryOffer"]
    existing = asc.get(
        f"/v1/subscriptions/{sub_id}/introductoryOffers?limit=200"
    )["data"]
    for current in existing:
        attrs = current["attributes"]
        if (attrs.get("offerMode") == offer["offerMode"]
                and attrs.get("duration") == offer["duration"]):
            print(f"intro offer — {offer['duration']} {offer['offerMode']} already set")
            return

    log("create intro offer", f"{offer['duration']} {offer['offerMode']}")
    if APPLY:
        asc.post(
            "/v1/subscriptionIntroductoryOffers",
            {
                "data": {
                    "type": "subscriptionIntroductoryOffers",
                    "attributes": {
                        "offerMode": offer["offerMode"],
                        "duration": offer["duration"],
                        "numberOfPeriods": offer["numberOfPeriods"],
                    },
                    "relationships": {
                        "subscription": {
                            "data": {"type": "subscriptions", "id": sub_id}
                        }
                    },
                }
            },
        )


def review_screenshot(sub_id: str) -> None:
    """Reserve → PUT → commit, the same dance as push_screenshots.py."""
    path = ROOT / CONFIG["reviewScreenshot"]
    existing = asc.get(f"/v1/subscriptions/{sub_id}/appStoreReviewScreenshot")
    if existing.get("data"):
        print("review screenshot — already uploaded")
        return

    if not path.exists():
        raise SystemExit(
            f"No review screenshot at {path}.\n"
            "Run ./tools/screenshots.sh — the 'paywall' scene produces it."
        )

    data = path.read_bytes()
    log("upload review screenshot", f"{path.name} ({len(data) // 1024} KB)")
    if not APPLY:
        return

    reserved = asc.post(
        "/v1/subscriptionAppStoreReviewScreenshots",
        {
            "data": {
                "type": "subscriptionAppStoreReviewScreenshots",
                "attributes": {"fileName": path.name, "fileSize": len(data)},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sub_id}}
                },
            }
        },
    )["data"]

    for operation in reserved["attributes"]["uploadOperations"]:
        offset = operation.get("offset", 0)
        length = operation.get("length", len(data))
        asc.upload(operation, data[offset:offset + length])

    asc.patch(
        f"/v1/subscriptionAppStoreReviewScreenshots/{reserved['id']}",
        {
            "data": {
                "type": "subscriptionAppStoreReviewScreenshots",
                "id": reserved["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(data).hexdigest(),
                },
            }
        },
    )


def main() -> None:
    if not APPLY:
        print("dry run — pass --apply to write\n")

    app_id = find_app()
    group_id = subscription_group(app_id)
    if not group_id:
        print("\nNothing further can be planned until the group exists. "
              "Re-run with --apply.")
        return
    group_localization(group_id)

    sub_id = subscription(group_id)
    if not sub_id:
        print("\nNothing further can be planned until the subscription exists. "
              "Re-run with --apply.")
        return

    localization(sub_id)
    price(sub_id)
    availability(sub_id)
    introductory_offer(sub_id)
    review_screenshot(sub_id)

    print("\nSubscription state is App Store Connect's to report — check that it "
          "reads 'Ready to Submit' before submitting the version.")


if __name__ == "__main__":
    main()
