#!/bin/sh
#
# Xcode Cloud looks for ci_scripts either at the repository root or alongside
# the .xcodeproj, and Apple's guidance says both. Those are different places
# here — the project lives in app/ — so this thin wrapper covers the
# project-adjacent case and delegates to the single real implementation at the
# repository root.
#
# Don't add logic here. Edit ../../ci_scripts/ci_post_clone.sh instead.
#
set -e
exec "${CI_PRIMARY_REPOSITORY_PATH}/ci_scripts/ci_post_clone.sh" "$@"
