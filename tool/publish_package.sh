#!/usr/bin/env bash
# Publishes one of the kit's four packages (PUBLISHING.md §Releasing), or dry-runs it.
#
#   tool/publish_package.sh voxel_engine --dry-run     # validate and print the file list
#   tool/publish_package.sh voxel_engine               # publish (pub asks to confirm)
#
# voxel_game publishes from this folder, where .pubignore keeps packages/ out of its tarball.
# The other three cannot publish in place: inside a git repository pub also applies the
# ignore files of every parent folder up to the git root, so that same `packages/` line hides
# a nested package from itself (its archive comes out empty, "the pubspec is hidden"), and a
# nested .pubignore cannot re-include it. Outside git pub reads only the package's own
# folders, so a nested package publishes from a copy of this folder with no .git in it —
# the whole workspace, so its sibling constraints resolve the same way they do here.
set -euo pipefail
cd "$(dirname "$0")/.."

package="${1:?usage: tool/publish_package.sh <voxel_engine|voxel_scene|sound_recipes|voxel_game> [--dry-run]}"
shift
mode=()
case "${1:-}" in
  --dry-run) mode=(--dry-run) ;;
  "") ;;
  *) echo "unknown flag: $1" >&2; exit 64 ;;
esac

case "$package" in
  voxel_game)
    flutter pub publish "${mode[@]}"
    ;;
  voxel_engine | voxel_scene | sound_recipes)
    copy="$(mktemp -d)/voxel_game"
    trap 'rm -rf "$(dirname "$copy")"' EXIT
    rsync -a --exclude .git --exclude build --exclude .dart_tool ./ "$copy/"
    (cd "$copy" && git rev-parse --show-toplevel >/dev/null 2>&1) \
      && { echo "the copy at $copy is inside a git repository; pub would hide the package" >&2; exit 70; }
    (cd "$copy" && flutter pub get >/dev/null)
    (cd "$copy/packages/$package" && flutter pub publish "${mode[@]}")
    ;;
  *)
    echo "not one of the kit's packages: $package" >&2
    exit 64
    ;;
esac
