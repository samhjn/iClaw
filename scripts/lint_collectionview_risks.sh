#!/bin/bash
# Lint for UICollectionView crash risk patterns in SwiftUI views.
# Run: bash scripts/lint_collectionview_risks.sh

set -euo pipefail
ROOT="${1:-.}"
SRC="$ROOT/iClaw"
EXIT=0

echo "=== UICollectionView Crash Risk Linter ==="
echo ""

# ── Pattern 1: @Query in non-root views ──────────────────────────
# @Query auto-fires on any modelContext.save(), causing cross-view
# batch update conflicts when multiple List views are mounted (TabView).
echo "── Pattern 1: @Query in views (cross-view observation risk) ──"
FOUND=$(grep -rn '@Query' "$SRC" --include='*.swift' \
    | grep -v '\.build/' | grep -v 'Tests/' | grep -v '//' || true)
if [ -n "$FOUND" ]; then
    echo "$FOUND"
    echo "⚠  @Query auto-fires on save() from ANY view. Use @State + manual fetch instead."
    EXIT=1
else
    echo "✓ No @Query found."
fi
echo ""

# ── Pattern 2: @Model relationship reads in ForEach rows ─────────
# Reading .count, .contains, .filter on @Model relationships inside
# ForEach registers SwiftData observation that can conflict with
# array-level batch updates.
echo "── Pattern 2: @Model relationship reads in row views ──"
# Look for common relationship access patterns in View structs
for f in $(find "$SRC" -name '*.swift' -path '*/Views/*'); do
    HITS=$(grep -n '\.\(sessions\|messages\|cronJobs\|installedSkills\|subAgents\|activeSkills\)\.\(count\|contains\|filter\|sorted\|first\|last\|isEmpty\)' "$f" || true)
    if [ -n "$HITS" ]; then
        echo "$f:"
        echo "$HITS"
        EXIT=1
    fi
done
if [ $EXIT -eq 0 ]; then
    echo "✓ No relationship reads found in views."
fi
echo ""

# ── Pattern 3: modelContext.delete without pre-update ────────────
# Calling modelContext.delete() + save() before updating the ForEach
# array causes SwiftData observation to fire before the array is
# consistent → item count mismatch.
echo "── Pattern 3: modelContext.delete() without pre-update ──"
for f in $(find "$SRC" -name '*.swift' ! -path '*/Tests/*'); do
    # Flag files that call modelContext.delete but are Views (not ViewModels)
    if grep -q 'modelContext\.delete' "$f" && echo "$f" | grep -q '/Views/'; then
        LINES=$(grep -n 'modelContext\.delete' "$f" || true)
        echo "$f:"
        echo "$LINES"
        echo "⚠  Views should not call modelContext.delete() directly."
        echo "   Deletion should go through a ViewModel that pre-updates arrays."
        EXIT=1
    fi
done
echo ""

if [ $EXIT -eq 0 ]; then
    echo "✅ No risks detected."
else
    echo "❌ Found potential UICollectionView crash risks."
fi
exit $EXIT
