#!/bin/sh
#
# Xcode Cloud: runs after each xcodebuild action.
#
# Auto-submits a release-branch archive for App Store review. Everything here
# is opt-in and fails soft — a broken submission must never fail a build that
# already produced a good archive.
#
set -e

echo "--- FinanceKitSync post-xcodebuild ---"

# Only the archive action produces something submittable; the build and test
# actions also run this script.
if [ "${CI_XCODEBUILD_ACTION}" != "archive" ]; then
    echo "action is ${CI_XCODEBUILD_ACTION:-unknown}, not archive; nothing to do"
    exit 0
fi

# Opt-in, and only from a release branch. Without both, this is a no-op — which
# is what keeps a manual Release run from auto-submitting behind your back.
if [ "${FKS_AUTO_SUBMIT:-0}" != "1" ]; then
    echo "FKS_AUTO_SUBMIT is not 1; skipping review submission"
    exit 0
fi

case "${CI_BRANCH}" in
    release|release/*) ;;
    *)
        echo "branch ${CI_BRANCH:-none} is not a release branch; skipping"
        exit 0
        ;;
esac

if [ -z "${ASC_KEY_ID}" ] || [ -z "${ASC_ISSUER_ID}" ] || [ -z "${ASC_KEY}" ]; then
    echo "WARNING: auto-submit is on but ASC credentials are missing."
    echo "         Set ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY (the .p8 contents,"
    echo "         as a secret environment variable) on this workflow."
    exit 0
fi

# The API client wants a key file, but Xcode Cloud only hands us environment
# variables — so materialise one in the temp dir for the life of this run.
ASC_KEY_PATH="${TMPDIR:-/tmp}/AuthKey_${ASC_KEY_ID}.p8"
printf '%s\n' "${ASC_KEY}" > "${ASC_KEY_PATH}"
chmod 600 "${ASC_KEY_PATH}"
export ASC_KEY_PATH

cleanup() { rm -f "${ASC_KEY_PATH}"; }
trap cleanup EXIT

python3 -m pip install --quiet --user cryptography || {
    echo "WARNING: could not install cryptography; skipping review submission"
    exit 0
}

# The archive uploads *after* this script, so the build will not exist yet —
# submit_for_review.py polls for it. --replace-queued is what makes a push to
# the release branch actually reach review when an older submission is already
# queued; without it the script would stop rather than forfeit that queue slot.
echo "submitting build ${CI_BUILD_NUMBER} for review"
python3 "${CI_PRIMARY_REPOSITORY_PATH}/tools/submit_for_review.py" \
    --build "${CI_BUILD_NUMBER}" \
    --replace-queued || {
        echo "WARNING: review submission failed. The archive is fine and"
        echo "         uploaded; submit from App Store Connect, or re-run"
        echo "         tools/submit_for_review.py locally."
    }

echo "--- post-xcodebuild done ---"
