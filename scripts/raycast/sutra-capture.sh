#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Leave Sutra Cue
# @raycast.mode compact
# @raycast.icon 🪡
# @raycast.packageName Sutra
# @raycast.description Drop an immediate next-action thread into Sutra working memory
# @raycast.argument1 { "type": "text", "placeholder": "Immediate next action..." }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_BIN="$SCRIPT_DIR/../../bin/sutra"

if command -v sutra >/dev/null 2>&1; then
    sutra capture --title "$1"
elif [ -x "$REPO_BIN" ]; then
    "$REPO_BIN" capture --title "$1"
elif [ -x "/usr/local/bin/sutra" ]; then
    /usr/local/bin/sutra capture --title "$1"
elif [ -x "/opt/homebrew/bin/sutra" ]; then
    /opt/homebrew/bin/sutra capture --title "$1"
else
    echo "Error: Sutra CLI binary not found." >&2
    exit 1
fi
