#!/bin/bash
# Build Goo Engine on an Apple Silicon Mac (M1/M2/M3/M4) and package a .dmg.
#
# Requirements: Xcode (or the Xcode Command Line Tools) and Homebrew.
# Usage: ./build_macos_arm64.sh
#
# Libraries, add-ons and assets are downloaded next to this checkout (../lib,
# about 5 GB). The build goes to ../build_goo_arm64 and the finished
# GooEngine-macos-arm64.dmg is written there too.

set -euo pipefail

# Date of the last upstream Blender main merge (Blender 4.1 alpha).
LIB_DATE="2024-01-31"
export CMAKE_POLICY_VERSION_MINIMUM=3.5

SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SRC")"
LIBDIR="$ROOT/lib/darwin_arm64"
BUILD="$ROOT/build_goo_arm64"

if [ "$(uname -m)" != "arm64" ]; then
  echo "This script must run natively on an Apple Silicon Mac (not under Rosetta)." >&2
  exit 1
fi

echo "==> Installing build tools"
brew install cmake ninja git-lfs
git lfs install --skip-repo

# Clone a projects.blender.org repo at the last commit before LIB_DATE.
fetch_at_date() {
  local url="$1" dest="$2" fallback="$3"
  if [ ! -d "$dest/.git" ]; then
    GIT_LFS_SKIP_SMUDGE=1 git clone --filter=blob:none --no-checkout "$url" "$dest"
  fi
  local ref
  ref="$(git -C "$dest" rev-list -1 --before="$LIB_DATE" origin/main || true)"
  [ -n "$ref" ] || ref="$fallback"
  GIT_LFS_SKIP_SMUDGE=1 git -C "$dest" checkout --quiet "$ref"
  git -C "$dest" lfs pull
  git -C "$dest" log -1 --format="    $(basename "$dest"): %h %cd"
}

echo "==> Fetching precompiled libraries (several GB, this takes a while)"
fetch_at_date https://projects.blender.org/blender/lib-macos_arm64.git "$LIBDIR" origin/blender-v4.1-release

echo "==> Fetching add-ons and assets"
fetch_at_date https://projects.blender.org/blender/blender-addons.git "$SRC/scripts/addons" origin/blender-v4.1-release || true
fetch_at_date https://projects.blender.org/blender/blender-addons-contrib.git "$SRC/scripts/addons_contrib" origin/blender-v4.1-release || true
fetch_at_date https://projects.blender.org/blender/blender-assets.git "$ROOT/lib/assets" origin/blender-v4.1-release || true

echo "==> Configuring"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
  -C "$SRC/build_files/cmake/config/blender_release.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DLIBDIR="$LIBDIR"

echo "==> Building (roughly 30-90 minutes)"
ninja -C "$BUILD" install

echo "==> Signing and packaging"
APP="$BUILD/bin/Blender.app"
# Every Mach-O file must carry a valid signature to run on Apple Silicon.
find "$APP" -type f \( -perm -u+x -o -name "*.dylib" -o -name "*.so" \) -print0 |
  while IFS= read -r -d '' f; do
    if file "$f" | grep -q "Mach-O"; then
      codesign --force --sign - "$f"
    fi
  done
codesign --force --sign - "$APP"

rm -rf "$BUILD/dmg"
mkdir -p "$BUILD/dmg"
cp -R "$APP" "$BUILD/dmg/Goo Engine.app"
ln -s /Applications "$BUILD/dmg/Applications"
hdiutil create -volname "Goo Engine" -srcfolder "$BUILD/dmg" -ov -format UDZO \
  "$BUILD/GooEngine-macos-arm64.dmg"

echo
echo "Done: $BUILD/GooEngine-macos-arm64.dmg"
echo "Or run directly: open \"$APP\""
