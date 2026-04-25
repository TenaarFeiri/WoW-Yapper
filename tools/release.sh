#!/usr/bin/env bash
set -euo pipefail

# Extract version from TOC
version=$(grep -E '^## Version:' Yapper.toc | head -1 | sed -E 's/^## Version:\s*//;s/\s*$//')
stage=.release/stage
out=.release/Yapper-"$version".zip

echo "Building Yapper v$version..."

# 0. Sync documentation before release
echo "Syncing documentation..."
./tools/sync.sh

# Clean start
rm -rf .release
mkdir -p "$stage/Yapper"

# 1. Main addon — strict whitelist of user-relevant files
rsync -a --include='Src/***' --include='Changelogs.md' --include='Yapper.lua' \
      --include='Yapper.toc' --include='Bindings.xml' \
      --exclude='*' ./ "$stage/Yapper/"

# 2. Ship these locales as sibling addons (deDE not ready yet)
for d in Yapper_Dict_en Yapper_Dict_enAU Yapper_Dict_enGB Yapper_Dict_enUS; do
    if [ -d "Dictionaries/$d" ]; then
        cp -r "Dictionaries/$d" "$stage/$d"
    fi
done

# 3. Zip with siblings at root
( cd "$stage" && zip -r -q "../../$out" . )

echo "--------------------------------------------------"
echo "Successfully built: $out"
echo "Structure inside ZIP:"
# Pipe to head can cause SIGPIPE (exit 141), which we ignore for the preview
unzip -l "$out" | grep -E "Yapper/|Yapper_Dict_" | head -n 12 || true
echo "..."
