#!/bin/bash
#
# Rebuild the MicroPython embed port and sync generated C files into the project.
# Run this after modifying mpconfigport.h or updating the MicroPython source.
#
# Usage: ./scripts/rebuild_micropython.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/vendor/micropython-build"
EMBED_TARGET="$PROJECT_ROOT/iClaw/MicroPython/micropython_embed"

echo "==> Syncing mpconfigport.h to build directory..."
cp "$PROJECT_ROOT/iClaw/MicroPython/mpconfigport.h" "$BUILD_DIR/mpconfigport.h"

echo "==> Cleaning previous embed build..."
cd "$BUILD_DIR"
make -f micropython_embed.mk clean

echo "==> Building embed port..."
make -f micropython_embed.mk

echo "==> Syncing generated files to project (preserving custom mphalport.c)..."
cp -R "$BUILD_DIR/micropython_embed/py" "$EMBED_TARGET/"
cp -R "$BUILD_DIR/micropython_embed/extmod" "$EMBED_TARGET/"
cp -R "$BUILD_DIR/micropython_embed/shared" "$EMBED_TARGET/"
cp -R "$BUILD_DIR/micropython_embed/genhdr" "$EMBED_TARGET/"
cp "$BUILD_DIR/micropython_embed/port/micropython_embed.h" "$EMBED_TARGET/port/"
cp "$BUILD_DIR/micropython_embed/port/mpconfigport_common.h" "$EMBED_TARGET/port/"
cp "$BUILD_DIR/micropython_embed/port/mphalport.h" "$EMBED_TARGET/port/"
cp "$BUILD_DIR/micropython_embed/port/embed_util.c" "$EMBED_TARGET/port/"

echo "==> Done! Custom mphalport.c preserved."
echo "    Run 'xcodegen generate' if project.yml has changed."
