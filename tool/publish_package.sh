#!/usr/bin/env bash
# Publishes one of the kit's four packages (PUBLISHING.md §Releasing), or dry-runs it.
#
#   tool/publish_package.sh voxel_engine --dry-run     # validate and print the file list
#   tool/publish_package.sh voxel_engine               # publish (pub asks to confirm)
#
# Every package lives under packages/ and the repository root is only the workspace, so each
# publishes in place: pub bundles the package's own folder, filtered by the .gitignore files
# from the git root down to it, and no parent folder holds a package that has to be hidden.
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
  voxel_engine | voxel_scene | sound_recipes | voxel_game) ;;
  *) echo "not one of the kit's packages: $package" >&2; exit 64 ;;
esac

flutter pub get >/dev/null
cd "packages/$package" && flutter pub publish ${mode[@]+"${mode[@]}"}
