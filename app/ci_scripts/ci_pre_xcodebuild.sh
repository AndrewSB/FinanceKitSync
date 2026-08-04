#!/bin/sh
#
# Wrapper — see ci_post_clone.sh in this directory for why it exists.
# Don't add logic here. Edit ../../ci_scripts/ci_pre_xcodebuild.sh instead.
#
set -e
exec "${CI_PRIMARY_REPOSITORY_PATH}/ci_scripts/ci_pre_xcodebuild.sh" "$@"
