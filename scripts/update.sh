#!/usr/bin/env bash

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.2.3"
    exit 1
fi

VERSION="$1"
PACKAGE_FILE="package.nix"

echo "Updating to Codex CLI version $VERSION..."

echo "Fetching SHA256 hash for version $VERSION..."
URL="https://registry.npmjs.org/@openai/codex-cli/-/codex-cli-${VERSION}.tgz"
HASH=$(nix-prefetch-url "$URL" 2>/dev/null || echo "")

if [ -z "$HASH" ]; then
    echo "Error: Could not fetch hash for version $VERSION"
    echo "The package might not exist or the version might be incorrect"
    exit 1
fi

echo "SHA256 hash: $HASH"

echo "Updating $PACKAGE_FILE..."
sed -i.bak "s/version = \".*\"/version = \"$VERSION\"/" "$PACKAGE_FILE"
sed -i.bak "s/sha256 = \".*\"/sha256 = \"$HASH\"/" "$PACKAGE_FILE"
rm -f "${PACKAGE_FILE}.bak"

echo "Testing build..."
if nix build --no-link; then
    echo "✅ Build successful!"
    echo ""
    echo "Version $VERSION has been successfully updated."
    echo "Don't forget to:"
    echo "  1. Test the new version: nix run . -- --version"
    echo "  2. Commit your changes"
    echo "  3. Push to GitHub"
else
    echo "❌ Build failed. Please check the error messages above."
    exit 1
fi