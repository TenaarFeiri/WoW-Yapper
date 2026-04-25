#!/bin/bash
# Sync documentation line numbers and inject missing functions.

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( dirname "$SCRIPT_DIR" )"

echo "--- Synchronising Documentation ---"
python3 "$SCRIPT_DIR/sync_all_docs.py" --inject
echo "--- Done ---"
