#!/bin/sh

cd "$CI_PRIMARY_REPOSITORY_PATH" 2>/dev/null || true

if [ -n "$CI_BUILD_NUMBER" ]; then
    echo "=== [ci_pre_xcodebuild] Setting build number to $CI_BUILD_NUMBER ==="
    if agvtool new-version -all "$CI_BUILD_NUMBER" 2>/dev/null; then
        echo "=== [ci_pre_xcodebuild] Build number updated ==="
    else
        echo "=== [ci_pre_xcodebuild] Skipping — no Xcode project (test workflow) ==="
    fi
else
    echo "=== [ci_pre_xcodebuild] CI_BUILD_NUMBER not set, skipping ==="
fi
