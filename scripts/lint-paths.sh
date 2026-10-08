#!/bin/bash
set -euo pipefail

# scripts/lint-paths.sh — Path Sanitization Linter
# Scans tracked sources for accidental hardcoded personal absolute paths.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "🔍 Scanning codebase for personal absolute paths..."

PATTERNS=(
    "/Users/[a-zA-Z0-9_-]+"
    "/home/[a-zA-Z0-9_-]+"
    "C:\\\\Users\\\\[a-zA-Z0-9_-]+"
)

EXCLUDES=(
    ":!sessions"
    ":!knowledge"
    ":!wiki"
    ":!.continuum"
    ":!plans"
    ":!target"
    ":!.build"
    ":!dist"
    ":!scripts/lint-paths.sh"
)

FOUND=0

for pattern in "${PATTERNS[@]}"; do
    MATCHES=$(git grep -E -I "$pattern" -- . "${EXCLUDES[@]}" 2>/dev/null || true)
    if [ -n "$MATCHES" ]; then
        echo "❌ Leaked personal path detected with pattern: $pattern"
        echo "$MATCHES"
        FOUND=1
    fi
done

if [ "$FOUND" -eq 1 ]; then
    echo ""
    echo "🚨 Path linting FAILED. Replace hardcoded absolute paths with dynamic bundle or relative paths."
    exit 1
fi

echo "✅ Path linting PASSED: Zero leaked personal absolute paths in tracked sources."
exit 0
