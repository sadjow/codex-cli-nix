#!/usr/bin/env bash
set -euo pipefail

repository=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

printf 'Repository settings: https://github.com/%s/settings\n\n' "$repository"
cat "$script_dir/../.github/REPOSITORY_SETTINGS.md"
