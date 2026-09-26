#!/bin/bash
# Add the standard six reactions (+1, laugh, hooray, heart, rocket, eyes) to a
# tw93/Mole release. Usage: post-reactions.sh V<version>

set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
    echo "Usage: $0 V<version>" >&2
    exit 1
fi

if [[ "$TAG" != V* ]]; then
    echo "Tag must start with capital V (release.yml ignores lowercase v): $TAG" >&2
    exit 1
fi

if ! command -v gh > /dev/null 2>&1; then
    echo "gh CLI is required" >&2
    exit 1
fi

RELEASE_ID=$(gh api "repos/tw93/Mole/releases/tags/$TAG" --jq '.id')
if [[ -z "$RELEASE_ID" ]]; then
    echo "Release not found for tag: $TAG" >&2
    exit 1
fi

for r in +1 laugh hooray heart rocket eyes; do
    gh api "repos/tw93/Mole/releases/$RELEASE_ID/reactions" \
        -X POST -f content="$r" --silent
done

echo "Posted 6 reactions to $TAG (release id $RELEASE_ID)"
