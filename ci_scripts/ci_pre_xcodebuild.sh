#!/bin/sh
#
# Xcode Cloud: runs immediately before each xcodebuild invocation.
#
set -e

echo "--- FinanceKitSync pre-xcodebuild ---"

# Xcode Cloud assigns a monotonically increasing build number per workflow.
# Feed it into the project so TestFlight builds don't collide, rather than
# committing a bumped CURRENT_PROJECT_VERSION on every release.
if [ -n "${CI_BUILD_NUMBER}" ]; then
    echo "setting build number to ${CI_BUILD_NUMBER}"
    cd "${CI_PRIMARY_REPOSITORY_PATH}/app"
    agvtool new-version -all "${CI_BUILD_NUMBER}" || \
        echo "agvtool failed; falling back to the project's CURRENT_PROJECT_VERSION"
fi

echo "--- pre-xcodebuild done ---"
