#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Read current version from package.json
current=$(grep '"version"' package.json | head -1 | sed 's/.*"\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/')
major=$(echo "$current" | cut -d. -f1)
minor=$(echo "$current" | cut -d. -f2)
patch=$(echo "$current" | cut -d. -f3)

# Bump patch
new_patch=$((patch + 1))
new_version="${major}.${minor}.${new_patch}"

echo "Bumping version: ${current} -> ${new_version}"

# Update package.json
sed -i "s/\"version\": \"${current}\"/\"version\": \"${new_version}\"/" package.json

# Update LSP server version in lsp_json.zig
lsp_json="../../src/lsp/lsp_json.zig"
if [ -f "$lsp_json" ]; then
    sed -i "s/\"version\":\"${current}\"/\"version\":\"${new_version}\"/" "$lsp_json"
    echo "Updated LSP server version in lsp_json.zig"
fi

# Remove old .vsix files
rm -f orhon-*.vsix

# Build the extension
npx @vscode/vsce package --no-dependencies

echo "Built orhon-${new_version}.vsix"
