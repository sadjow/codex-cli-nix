#!/usr/bin/env bash
set -euo pipefail

VERSION=${1:?Usage: update-moving-tags.sh VERSION}
if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 1
fi
MAJOR=${VERSION%%.*}

# Record the remote values before changing anything. Explicit leases also
# protect against another writer updating either channel during this run.
REMOTE_TAGS=$(git ls-remote --refs origin refs/tags/latest "refs/tags/v$MAJOR")
LATEST_SHA=$(awk '$2 == "refs/tags/latest" { print $1 }' <<< "$REMOTE_TAGS")
MAJOR_SHA=$(awk -v ref="refs/tags/v$MAJOR" '$2 == ref { print $1 }' <<< "$REMOTE_TAGS")

# A rerun of an older build must not move the channels back behind a release
# that has already been published from a newer commit.
if [[ -n $LATEST_SHA ]]; then
  git fetch --quiet origin "+refs/tags/latest:refs/tags/latest"
  PUBLISHED_COMMIT=$(git rev-parse 'refs/tags/latest^{commit}')
  if [[ $PUBLISHED_COMMIT != "$(git rev-parse HEAD)" ]] && git merge-base --is-ancestor HEAD "$PUBLISHED_COMMIT"; then
    echo "latest already points to the newer commit $PUBLISHED_COMMIT; leaving moving tags unchanged"
    exit 0
  fi
fi

git tag -f -a latest -m "Latest release: v$VERSION" HEAD
git tag -f -a "v$MAJOR" -m "Latest v$MAJOR release: v$VERSION" HEAD

# Never delete live channel refs. GitHub applies both updates or neither,
# including when one ref is rejected. Empty leases allow missing tags to be
# recreated, but only if they are still absent at push time.
git push --atomic \
  "--force-with-lease=refs/tags/latest:$LATEST_SHA" \
  "--force-with-lease=refs/tags/v$MAJOR:$MAJOR_SHA" \
  origin refs/tags/latest:refs/tags/latest "refs/tags/v$MAJOR:refs/tags/v$MAJOR"
