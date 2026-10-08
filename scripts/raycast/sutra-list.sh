#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title List Sutra Threads
# @raycast.mode fullOutput
# @raycast.icon 🪡
# @raycast.packageName Sutra
# @raycast.description Show all waiting threads in Sutra working memory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_BIN="$SCRIPT_DIR/../../bin/sutra"

if command -v sutra >/dev/null 2>&1; then
    sutra list
elif [ -x "$REPO_BIN" ]; then
    "$REPO_BIN" list
elif [ -x "/usr/local/bin/sutra" ]; then
    /usr/local/bin/sutra list
elif [ -x "/opt/homebrew/bin/sutra" ]; then
    /opt/homebrew/bin/sutra list
else
    echo "Error: Sutra CLI binary not found." >&2
    exit 1
fi
