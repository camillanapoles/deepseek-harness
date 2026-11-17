#!/usr/bin/env bash
# Publish the built rootfs tarballs, regenerate the Droidspaces feed, and
# record the regenerated feed in the repository.
#
# The script runs in the publish job of .github/workflows/droidspaces-rootfs.yml
# with the built tarballs in the current directory.
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

FEED_PATH=droidspaces/rootfs.json
TARGET_BRANCH=${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}
TAG=${DSH_ROOTFS_TAG:-droidspaces-rootfs-v$(date -u +%Y%m%d-%H%M%S)}

shopt -s nullglob
ASSETS=(droidspaces/*-Droidspaces-rootfs-*.tar.xz)
shopt -u nullglob
if [ ${#ASSETS[@]} -eq 0 ]; then
  echo "error: no rootfs tarball to publish" >&2
  exit 1
fi

echo "publishing ${#ASSETS[@]} assets as $TAG"
gh release create "$TAG" \
  --title "DeepSeek Harness rootfs $TAG" \
  --notes "DeepSeek Harness rootfs images for Droidspaces. The feed that lists them is \`$FEED_PATH\`; subscribe to it in the app with **Manage Repositories**." \
  --target "$TARGET_BRANCH" \
  "${ASSETS[@]}"

# The feed is generated from the published release, so the download addresses
# and the digests come from the assets the app downloads.
python3 droidspaces/scripts/generate_rootfs_json.py --release "$TAG" --assets droidspaces

# The same file is attached to the release, which gives the feed a permanent
# address that no branch move can take away.
gh release upload "$TAG" "$FEED_PATH" --clobber

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add "$FEED_PATH"
if git diff --cached --quiet; then
  echo "the feed did not change"
else
  git commit -m "chore(droidspaces): regenerate the rootfs feed for $TAG"
  git push origin "HEAD:$TARGET_BRANCH"
fi

echo "published $TAG"
gh release view "$TAG" --json url --jq .url
