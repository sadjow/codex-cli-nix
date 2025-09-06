#!/usr/bin/env bash

set -euo pipefail

PACKAGE_FILE="package.nix"

usage() {
    echo "Usage: $0 [--check | <version>]"
    echo ""
    echo "Options:"
    echo "  --check     Check if a new version is available"
    echo "  <version>   Update to a specific version (e.g., 0.30.0)"
    echo ""
    echo "Examples:"
    echo "  $0 --check"
    echo "  $0 0.30.0"
    exit 1
}

get_current_version() {
    grep 'version = ' "$PACKAGE_FILE" | cut -d'"' -f2
}

get_latest_version() {
    curl -s https://registry.npmjs.org/@openai/codex/latest | \
        sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
}

if [ $# -eq 0 ]; then
    usage
fi

if [ "$1" = "--check" ]; then
    CURRENT_VERSION=$(get_current_version)
    LATEST_VERSION=$(get_latest_version)
    
    echo "Current version: $CURRENT_VERSION"
    echo "Latest version:  $LATEST_VERSION"
    
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo "✅ Already up to date!"
        exit 0
    else
        echo "🆕 New version available: $LATEST_VERSION"
        echo "Run './scripts/update.sh $LATEST_VERSION' to update"
        exit 1
    fi
fi

VERSION="$1"

echo "Updating to Codex CLI version $VERSION..."

echo "Fetching SHA256 hash for version $VERSION..."
URL="https://registry.npmjs.org/@openai/codex/-/codex-${VERSION}.tgz"
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