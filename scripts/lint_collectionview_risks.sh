#!/bin/bash
# Lint for SwiftUI List crash risk patterns.
# Run: bash scripts/lint_collectionview_risks.sh [source_root]
#
# The primary crash pattern: using a custom Binding(get:set:) derived
# from @Observable state as isPresented for alert/sheet/confirmationDialog
# on a View that contains a List. SwiftUI evaluates these bindings via
# dispatchImmediately during dismissal, re-entering the render cycle
# while a List batch update is in flight → UICollectionView item count
# mismatch crash.

set -euo pipefail
ROOT="${1:-.}"
SRC="$ROOT/iClaw"
EXIT=0

echo "=== SwiftUI List Crash Risk Linter ==="
echo ""

# ── Primary pattern: custom Binding on isPresented ───────────────
# alert/sheet/confirmationDialog with Binding(get:set:) triggers
# dispatchImmediately during dismissal. Use @State bool instead.
echo "── Custom Binding on isPresented (dispatchImmediately crash) ──"
FOUND=$(grep -rn 'isPresented: Binding(' "$SRC" --include='*.swift' \
    | grep -v '\.build/' | grep -v 'Tests/' || true)
if [ -n "$FOUND" ]; then
    echo "$FOUND"
    echo ""
    echo "⚠  Custom Binding(get:set:) on isPresented triggers dispatchImmediately"
    echo "   during dismissal, re-entering the render cycle. Use @State bool instead:"
    echo "   @State private var showAlert = false"
    echo "   .alert(..., isPresented: \$showAlert)"
    EXIT=1
else
    echo "✓ No custom Binding on isPresented found."
fi
echo ""

if [ $EXIT -eq 0 ]; then
    echo "✅ No risks detected."
else
    echo "❌ Found potential crash risks. See above for details."
fi
exit $EXIT
