#!/usr/bin/env bash
# Build one Droidspaces rootfs for one architecture.
#
#   ./droidspaces/build.sh -a <arch> -i <Name> [-v <version>]
#
# <arch> is a key in droidspaces/archs.json and a folder under
# droidspaces/templates/. <Name> is
# droidspaces/templates/<arch>/<Name>.Dockerfile. The build context is the
# repository root, so every template copies the same scripts.
#
# Output: <Name>-Droidspaces-rootfs-<arch>-<YYYYMMDD>-<version>.tar.xz
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

ARCH=""
NAME=""
VERSION="dev"
while getopts ":a:i:v:" opt; do
  case "$opt" in
    a) ARCH="$OPTARG" ;;
    i) NAME="${OPTARG%.Dockerfile}" ;;
    v) VERSION="$OPTARG" ;;
    *) echo "Usage: $0 -a <arch> -i <Name> [-v <version>]" >&2; exit 1 ;;
  esac
done
if [ -z "$ARCH" ] || [ -z "$NAME" ]; then
  echo "Usage: $0 -a <arch> -i <Name> [-v <version>]" >&2
  exit 1
fi

DOCKERFILE="$SCRIPT_DIR/templates/$ARCH/$NAME.Dockerfile"
if [ ! -f "$DOCKERFILE" ]; then
  echo "Error: $DOCKERFILE not found" >&2
  exit 1
fi

PLATFORM=$(jq -er --arg a "$ARCH" '.[$a].platform' archs.json) || {
  echo "Error: arch '$ARCH' not in archs.json" >&2
  exit 1
}

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
BUILD_DATE=$(date +%Y%m%d)
FINAL_NAME="$SCRIPT_DIR/${NAME}-Droidspaces-rootfs-${ARCH}-${BUILD_DATE}-${VERSION}.tar.xz"
TEMP_TAR="$SCRIPT_DIR/${NAME}-rootfs-${ARCH}.tar"

echo "========================================================="
echo " Template : $DOCKERFILE"
echo " Platform : $PLATFORM"
echo " Version  : $VERSION"
echo "========================================================="

# Register QEMU handlers only when the host cannot run the target natively.
if ! docker run --rm --platform "$PLATFORM" alpine:3.23 true >/dev/null 2>&1; then
  echo "Host cannot run $PLATFORM natively; installing binfmt/QEMU..."
  docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
fi

BUILDER=droidspaces-builder
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null
else
  docker buildx use "$BUILDER" >/dev/null
fi
docker buildx inspect --bootstrap >/dev/null

cd "$REPO_ROOT"
docker buildx build \
  --progress=plain \
  --platform "$PLATFORM" \
  --target export \
  --output "type=tar,dest=$TEMP_TAR" \
  -f "$DOCKERFILE" \
  .

# The app accepts a tarball only when it holds a Linux root filesystem at the
# top level, so the archive is checked before it is compressed.
for entry in bin sbin etc usr; do
  if ! tar -tf "$TEMP_TAR" | grep -qE "^(\./)?$entry(/|$)"; then
    echo "Error: the built archive has no top-level '$entry' entry" >&2
    tar -tf "$TEMP_TAR" | head -20 >&2
    exit 1
  fi
done

echo "Compressing (xz -T0 -6)..."
xz -T0 -6 -f "$TEMP_TAR"
mv "${TEMP_TAR}.xz" "$FINAL_NAME"

echo "========================================================="
echo " Done: $FINAL_NAME"
echo "========================================================="
