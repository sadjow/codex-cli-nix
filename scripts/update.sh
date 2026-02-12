#!/usr/bin/env bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly GITHUB_REPO="openai/codex"
readonly NPM_REGISTRY_URL="https://registry.npmjs.org"
readonly NPM_PACKAGE_NAME="@openai/codex"
readonly GITHUB_RELEASE_BASE="https://github.com/${GITHUB_REPO}/releases/download"

readonly NATIVE_PLATFORMS=("aarch64-apple-darwin" "x86_64-apple-darwin" "x86_64-unknown-linux-gnu" "aarch64-unknown-linux-gnu")
readonly NODE_PLATFORMS=("darwin-arm64" "darwin-x64" "linux-x64" "linux-arm64")

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_current_version() {
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' package.nix | head -1 || echo "unknown"
}

get_latest_version() {
    local tag
    tag=$(gh release view --repo "$GITHUB_REPO" --json tagName -q '.tagName' 2>/dev/null || echo "")
    if [ -z "$tag" ]; then
        log_error "Failed to fetch latest version from GitHub"
        exit 1
    fi
    echo "$tag" | sed 's/^rust-v//'
}

fetch_native_hash() {
    local version="$1"
    local platform="$2"
    local url="${GITHUB_RELEASE_BASE}/rust-v${version}/codex-${platform}.tar.gz"

    local hash
    hash=$(nix-prefetch-url "$url" 2>/dev/null | tail -1)
    echo "$hash" | tr -d '\n'
}

fetch_npm_hash() {
    local version="$1"
    local url="${NPM_REGISTRY_URL}/${NPM_PACKAGE_NAME}/-/codex-${version}.tgz"

    local hash
    hash=$(nix-prefetch-url "$url" 2>/dev/null | tail -1)
    echo "$hash" | tr -d '\n'
}

fetch_node_optional_dep_hash() {
    local version="$1"
    local platform="$2"
    local url="${NPM_REGISTRY_URL}/${NPM_PACKAGE_NAME}/-/codex-${version}-${platform}.tgz"

    local hash
    hash=$(nix-prefetch-url "$url" 2>/dev/null | tail -1)
    echo "$hash" | tr -d '\n'
}

update_package_version() {
    local version="$1"
    sed -i.bak "s/version = \".*\"/version = \"$version\"/" package.nix
}

update_npm_hash() {
    local hash="$1"
    local temp_file
    temp_file=$(mktemp)
    awk -v hash="$hash" '
        /npmTarball = / { in_tarball_block=1 }
        in_tarball_block && /fetchurl/ { in_fetchurl_block=1 }
        in_fetchurl_block && /sha256 = / {
            sub(/sha256 = "[^"]*"/, "sha256 = \"" hash "\"")
            in_tarball_block=0
            in_fetchurl_block=0
        }
        in_tarball_block && /^[[:space:]]*else/ { in_tarball_block=0 }
        { print }
    ' package.nix > "$temp_file"
    mv "$temp_file" package.nix
}

update_native_hash() {
    local platform="$1"
    local hash="$2"
    local temp_file
    temp_file=$(mktemp)

    awk -v platform="$platform" -v hash="$hash" '
        /nativeHashes = \{/ { in_native_block=1 }
        in_native_block && $0 ~ "\"" platform "\"" {
            sub(/= "[^"]*"/, "= \"" hash "\"")
        }
        in_native_block && /\};/ { in_native_block=0 }
        { print }
    ' package.nix > "$temp_file"
    mv "$temp_file" package.nix
}

update_node_optional_dep_hash() {
    local platform="$1"
    local hash="$2"
    local temp_file
    temp_file=$(mktemp)

    awk -v platform="$platform" -v hash="$hash" '
        /nodeOptionalDepHashes = \{/ { in_block=1 }
        in_block && $0 ~ "\"" platform "\"" {
            sub(/= "[^"]*"/, "= \"" hash "\"")
        }
        in_block && /\};/ { in_block=0 }
        { print }
    ' package.nix > "$temp_file"
    mv "$temp_file" package.nix
}

cleanup_backup_files() {
    rm -f package.nix.bak
}

update_to_version() {
    local new_version="$1"

    log_info "Updating to version $new_version..."

    update_package_version "$new_version"

    log_info "Fetching native binary hashes..."
    for platform in "${NATIVE_PLATFORMS[@]}"; do
        log_info "  Fetching hash for $platform..."
        local native_hash
        native_hash=$(fetch_native_hash "$new_version" "$platform")
        if [ -z "$native_hash" ]; then
            log_error "Failed to fetch native hash for $platform"
            mv package.nix.bak package.nix
            exit 1
        fi
        log_info "  $platform: $native_hash"
        update_native_hash "$platform" "$native_hash"
    done

    log_info "Fetching npm tarball hash..."
    local npm_hash
    npm_hash=$(fetch_npm_hash "$new_version")
    if [ -z "$npm_hash" ]; then
        log_error "Failed to fetch npm tarball hash"
        mv package.nix.bak package.nix
        exit 1
    fi
    log_info "NPM tarball hash: $npm_hash"
    update_npm_hash "$npm_hash"

    log_info "Fetching node platform-specific dependency hashes..."
    for node_platform in "${NODE_PLATFORMS[@]}"; do
        log_info "  Fetching hash for $node_platform..."
        local node_dep_hash
        node_dep_hash=$(fetch_node_optional_dep_hash "$new_version" "$node_platform")
        if [ -z "$node_dep_hash" ]; then
            log_error "Failed to fetch node optional dep hash for $node_platform"
            mv package.nix.bak package.nix
            exit 1
        fi
        log_info "  $node_platform: $node_dep_hash"
        update_node_optional_dep_hash "$node_platform" "$node_dep_hash"
    done

    cleanup_backup_files

    log_info "Verifying builds..."

    log_info "  Building codex (native)..."
    if ! nix build .#codex > /dev/null 2>&1; then
        log_error "Native build verification failed"
        return 1
    fi

    log_info "  Building codex-node..."
    if ! nix build .#codex-node > /dev/null 2>&1; then
        log_error "Node build verification failed"
        return 1
    fi

    log_info "✅ All builds successful!"
    return 0
}

ensure_in_repository_root() {
    if [ ! -f "flake.nix" ] || [ ! -f "package.nix" ]; then
        log_error "flake.nix or package.nix not found. Please run this script from the repository root."
        exit 1
    fi
}

ensure_required_tools_installed() {
    command -v nix >/dev/null 2>&1 || { log_error "nix is required but not installed."; exit 1; }
    command -v nix-prefetch-url >/dev/null 2>&1 || { log_error "nix-prefetch-url is required but not installed."; exit 1; }
    command -v gh >/dev/null 2>&1 || { log_error "gh (GitHub CLI) is required but not installed."; exit 1; }
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VERSION  Update to specific version"
    echo "  --check           Only check for updates, don't apply"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Update to latest version"
    echo "  $0 --check            # Check if update is available"
    echo "  $0 --version 0.92.0   # Update to specific version"
}

parse_arguments() {
    local target_version=""
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --check)
                check_only=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    echo "$target_version|$check_only"
}

update_flake_lock() {
    if command -v nix >/dev/null 2>&1; then
        log_info "Updating flake.lock..."
        nix flake update
    fi
}

show_changes() {
    echo ""
    log_info "Changes made:"
    git diff --stat package.nix flake.lock 2>/dev/null || true
}

main() {
    ensure_in_repository_root
    ensure_required_tools_installed

    local args
    args=$(parse_arguments "$@")
    local target_version
    target_version=$(echo "$args" | cut -d'|' -f1)
    local check_only
    check_only=$(echo "$args" | cut -d'|' -f2)

    local current_version
    current_version=$(get_current_version)
    local latest_version
    latest_version=$(get_latest_version)

    if [ -n "$target_version" ]; then
        latest_version="$target_version"
    fi

    log_info "Current version: $current_version"
    log_info "Latest version: $latest_version"

    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date!"
        exit 0
    fi

    if [ "$check_only" = true ]; then
        log_info "Update available: $current_version → $latest_version"
        exit 1
    fi

    update_to_version "$latest_version"

    log_info "Successfully updated codex from $current_version to $latest_version"

    update_flake_lock
    show_changes
}

main "$@"
