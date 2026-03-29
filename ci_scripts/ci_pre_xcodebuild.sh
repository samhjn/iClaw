#!/bin/sh
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ -n "$CI_BUILD_NUMBER" ]; then
    echo "=== [ci_pre_xcodebuild] Setting build number to $CI_BUILD_NUMBER ==="
    agvtool new-version -all "$CI_BUILD_NUMBER"
    echo "=== [ci_pre_xcodebuild] Build number updated ==="
else
    echo "=== [ci_pre_xcodebuild] CI_BUILD_NUMBER not set, skipping ==="
fi
