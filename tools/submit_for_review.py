"""Attach the newest Xcode Cloud build to the App Store version and submit it
for review.

Xcode Cloud stops at *uploading* a build — there is no Archive action, post
action, or workflow setting that creates a review submission. That last step is
App Store Connect API only, which is what this script is for. Run it after an
archive lands and the release is hands-off end to end.

    export ASC_KEY_ID=...
    export ASC_ISSUER_ID=...
    export ASC_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8

    python3 tools/submit_for_review.py --build 20            # submit build 20
    python3 tools/submit_for_review.py --build 20 --dry-run  # say what it would do

Safe to re-run: every step checks the current state first, so a run that dies
waiting for processing can simply be run again.

## The part that surprises people

A submission in WAITING_FOR_REVIEW cannot have its build swapped. Apple treats
a queued submission as frozen, so "replace the build" really means *cancel the
old submission and create a new one*. This script does that, and it means
submitting a fix costs you your place in the review queue. There is no way
around it — the queued submission carries the old binary by definition.

Cancelling is destructive and outward-facing, so it needs --replace-queued.
Without that flag the script stops and tells you what is in the way.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

import asc

BUNDLE_ID = "com.asb.FinanceKitSync"
PLATFORM = "IOS"

# States a submission can sit in that block creating a new one. READY_FOR_REVIEW
# is the "created but never submitted" state — a leftover from a half-finished
# run, and the one case we can clear without losing anything real.
BLOCKING_STATES = ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW")


def find_app() -> str:
    apps = asc.get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}").get("data", [])
    if not apps:
        raise SystemExit(f"no app found for bundle ID {BUNDLE_ID}")
    return apps[0]["id"]


def find_editable_version(app_id: str) -> dict:
    """The version record a new build can be attached to.

    Anything not in a live-on-the-store state is fair game; Apple returns them
    newest first, so the first editable one is the release in flight.
    """
    versions = asc.get(
        f"/v1/apps/{app_id}/appStoreVersions?limit=10"
    ).get("data", [])
    for version in versions:
        state = version["attributes"].get("appStoreState")
        if state not in ("READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION"):
            return version
    raise SystemExit(
        "no editable App Store version — create the next version in "
        "App Store Connect before submitting"
    )


def wait_for_build(app_id: str, build_number: str, timeout_s: int) -> dict:
    """Block until the build exists and Apple has finished processing it.

    An uploaded build is not immediately attachable: it sits in PROCESSING for
    anywhere from a couple of minutes to well over half an hour, and attaching
    it before then fails.
    """
    deadline = time.time() + timeout_s
    reported_processing = False

    while True:
        builds = asc.get(
            f"/v1/builds?filter[app]={app_id}&filter[version]={build_number}&limit=1"
        ).get("data", [])

        if builds:
            build = builds[0]
            state = build["attributes"].get("processingState")
            if state == "VALID":
                print(f"build {build_number} is processed ({build['id']})")
                return build
            if state in ("FAILED", "INVALID"):
                raise SystemExit(
                    f"build {build_number} finished processing as {state} — "
                    "check App Store Connect for the reason"
                )
            if not reported_processing:
                print(f"build {build_number} is {state}; waiting…")
                reported_processing = True
        elif not reported_processing:
            print(f"build {build_number} has not appeared yet; waiting…")

        if time.time() > deadline:
            raise SystemExit(
                f"gave up after {timeout_s}s waiting for build {build_number}. "
                "Nothing was submitted; re-run this script once it processes."
            )
        time.sleep(30)


def blocking_submissions(app_id: str) -> list[dict]:
    found = []
    for state in BLOCKING_STATES:
        found += asc.get(
            f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]={state}"
        ).get("data", [])
    return found


def cancel(submission: dict, dry_run: bool) -> None:
    state = submission["attributes"].get("state")
    print(f"cancelling submission {submission['id']} ({state})")
    if dry_run:
        return
    asc.patch(
        f"/v1/reviewSubmissions/{submission['id']}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission["id"],
                "attributes": {"canceled": True},
            }
        },
    )


def attach_build(version_id: str, build_id: str, dry_run: bool) -> None:
    print(f"attaching build {build_id} to version {version_id}")
    if dry_run:
        return
    asc.patch(
        f"/v1/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build_id}},
    )


def submit(app_id: str, version_id: str, dry_run: bool) -> None:
    print("creating review submission")
    if dry_run:
        print("creating submission item and submitting (dry run)")
        return

    submission = asc.post(
        "/v1/reviewSubmissions",
        {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": PLATFORM},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}}
                },
            }
        },
    )["data"]

    asc.post(
        "/v1/reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {
                            "type": "reviewSubmissions",
                            "id": submission["id"],
                        }
                    },
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version_id}
                    },
                },
            }
        },
    )

    # Creating a submission does not submit it — this PATCH is what actually
    # puts the app in front of Apple.
    result = asc.patch(
        f"/v1/reviewSubmissions/{submission['id']}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission["id"],
                "attributes": {"submitted": True},
            }
        },
    )
    state = result["data"]["attributes"].get("state")
    print(f"submitted — {submission['id']} is {state}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--build",
        default=os.environ.get("CI_BUILD_NUMBER"),
        help="build number to submit (defaults to $CI_BUILD_NUMBER)",
    )
    parser.add_argument(
        "--replace-queued",
        action="store_true",
        help="cancel a WAITING_FOR_REVIEW or IN_REVIEW submission first. "
             "This forfeits its place in the review queue.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=45 * 60,
        help="seconds to wait for the build to finish processing (default 2700)",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.build:
        raise SystemExit("no build number: pass --build or set CI_BUILD_NUMBER")

    app_id = find_app()
    version = find_editable_version(app_id)
    version_id = version["id"]
    version_string = version["attributes"].get("versionString")
    print(f"app {app_id}, version {version_string} ({version['attributes'].get('appStoreState')})")

    queued = blocking_submissions(app_id)
    # A never-submitted leftover is junk and can go regardless; a real queued
    # submission is the user's place in line and needs the explicit flag.
    real = [s for s in queued if s["attributes"].get("state") != "READY_FOR_REVIEW"]
    if real and not args.replace_queued:
        states = ", ".join(f"{s['id']} ({s['attributes'].get('state')})" for s in real)
        raise SystemExit(
            f"a submission is already in the queue: {states}\n"
            "Apple will not let its build be swapped. Re-run with "
            "--replace-queued to cancel it and submit a new one, knowing that "
            "forfeits its review queue position."
        )
    # Wait for the build BEFORE cancelling anything. The gate above already
    # failed fast if the queue is occupied, so the only thing left is to hold
    # the existing submission's place until there is something to replace it
    # with — a build that never processes should leave the queue untouched.
    build = wait_for_build(app_id, args.build, args.timeout)

    for submission in queued:
        cancel(submission, args.dry_run)

    attach_build(version_id, build["id"], args.dry_run)
    submit(app_id, version_id, args.dry_run)


if __name__ == "__main__":
    try:
        main()
    except KeyError as missing:
        raise SystemExit(f"missing environment variable: {missing}") from None
