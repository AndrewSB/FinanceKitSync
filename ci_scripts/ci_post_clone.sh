#!/bin/sh
#
# Xcode Cloud: runs after the repository is cloned, before dependencies resolve.
#
# Xcode Cloud looks for ci_scripts/ at the repository root, which is why this
# lives here rather than next to app/FinanceKitSync.xcodeproj.
#
set -e

echo "--- FinanceKitSync post-clone ---"
echo "workflow:  ${CI_WORKFLOW:-unknown}"
echo "branch:    ${CI_BRANCH:-none}"
echo "tag:       ${CI_TAG:-none}"
echo "pr:        ${CI_PULL_REQUEST_NUMBER:-none}"
echo "build:     ${CI_BUILD_NUMBER:-unknown}"

# --- FinanceKit entitlement gate -------------------------------------------
#
# Until Apple approves com.apple.developer.financekit for team A29347X2JZ and
# bundle ID com.asb.FinanceKitSync, any signed build fails with:
#
#   Entitlement com.apple.developer.financekit requires approval from Apple
#
# Set FKS_UNENTITLED=1 in the workflow's environment variables to build against
# the stripped entitlements file instead. That produces an installable app that
# cannot read financial data — fine for validating the pipeline, useless to
# ship. Remove the variable the moment the entitlement is approved.
#
if [ "${FKS_UNENTITLED:-0}" = "1" ]; then
    echo "WARNING: building WITHOUT the FinanceKit entitlement (FKS_UNENTITLED=1)."
    echo "         This build cannot read transactions. Do not distribute it."
    cp "${CI_PRIMARY_REPOSITORY_PATH}/app/Supporting/FinanceKitSync-Unentitled.entitlements" \
       "${CI_PRIMARY_REPOSITORY_PATH}/app/Supporting/FinanceKitSync.entitlements"
fi

echo "--- post-clone done ---"
