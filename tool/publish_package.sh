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
(cd "packages/$package" && dart format --output=none --set-exit-if-changed . >/dev/null) || {
  echo "packages/$package is not formatted: run dart format . there (pub.dev takes 10 points)" >&2
  exit 1
}

# pub.dev analyses a version as soon as it lands, and a dependency published seconds before
# is not yet visible to its analyser: the dependent scores 50 of 160 ("could not find package
# voxel_engine") until pub.dev reanalyses it. So a dependent waits until pub.dev has analysed
# the version of each kit package it depends on that this tree holds.
case "$package" in
  voxel_scene) deps=(voxel_engine) ;;
  voxel_game) deps=(voxel_engine sound_recipes voxel_scene) ;;
  *) deps=() ;;
esac
if [ ${#mode[@]} -eq 0 ]; then
  for dep in ${deps[@]+"${deps[@]}"}; do
    version="$(sed -n 's/^version: *//p' "packages/$dep/pubspec.yaml")"
    until curl -fsS "https://pub.dev/api/packages/$dep/metrics" | grep -q "\"packageVersion\":\"$version\""; do
      echo "waiting for pub.dev to analyse $dep $version..."
      sleep 30
    done
  done
fi

cd "packages/$package" && flutter pub publish ${mode[@]+"${mode[@]}"}
