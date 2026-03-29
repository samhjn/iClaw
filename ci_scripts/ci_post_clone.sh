#!/bin/sh
set -e

echo "=== [ci_post_clone] Installing XcodeGen ==="
brew install xcodegen

echo "=== [ci_post_clone] Generating Xcode Project ==="
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "=== [ci_post_clone] Done ==="
