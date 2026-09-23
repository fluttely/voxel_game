#!/usr/bin/env bash
# The performance loop of docs/PERFORMANCE_VS_GODOT_2026-09-11.md, as one command: release
# build, radius 8 / 12 / 16, fill time, sustained fps and peak memory per radius. The gates of
# VP1.5, VP2.2 and VP3 (docs/VOXEL_PACKAGES_PLAN_2026-09-14.md) read its summary.
#
#   tool/perf_loop.sh                          # build this POC in release, then measure it
#   tool/perf_loop.sh --no-build DIR           # measure an already built POC rooted at DIR
#   tool/perf_loop.sh --repeat 5 --cooldown 20 A=DIR_A B=DIR_B
#                                              # A/B: launches alternate A,B then B,A per round
#   tool/perf_loop.sh --radii "16" ...         # only these radii
#   tool/perf_loop.sh A=. B=.,--shadowcache=0   # one tree, extra launch flags after commas
#
# One launch carries about ±15% on sustained fps (thermal state, launch order), so a gate reads
# the medians of --repeat runs and holds only when the gap exceeds both spreads (VP3.0).
# Close other heavy work first: the numbers are wall-clock on the developer's machine.
set -euo pipefail
cd "$(dirname "$0")/.."

repeat=1 cooldown=0 radii="8 12 16" build=1
labels=() dirs=() extras=()
while (($#)); do
  case $1 in
    --repeat) repeat=${2:?}; shift 2 ;;
    --cooldown) cooldown=${2:?}; shift 2 ;;
    --radii) radii=${2:?}; shift 2 ;;
    --no-build) build=0; if [[ ${2:-} && ${2:-} != -* && ${2:-} != *=* ]]; then labels+=(poc); dirs+=("$2"); extras+=(""); shift; fi; shift ;;
    *=*) build=0; spec=${1#*=}; labels+=("${1%%=*}"); dirs+=("${spec%%,*}")
      extra=${spec#"${spec%%,*}"}; extras+=("${extra//,/ }"); shift ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done
if ((${#labels[@]} == 0)); then
  labels=(poc) dirs=(.) extras=("")
fi
if ((build)); then flutter build macos --release >/dev/null; fi

shots=$(mktemp -d)
raw=$shots/raw.tsv
: >"$raw"

measure() { # label dir radius extra-flags
  local app=$2/build/macos/Build/Products/Release/voxel_game_minecraft.app/Contents/MacOS/voxel_game_minecraft out
  [[ -x $app ]] || { echo "no release build at $app" >&2; exit 66; }
  out=$( { perl -e 'alarm 300; exec @ARGV' /usr/bin/time -l "$app" --new --seed=42 --radius="$3" \
    --frames=3000 --settle=900 --screenshot="$shots/$1-r$3.png" $4; } 2>&1 || true)
  local fill faces fps sfps rss
  fill=$(grep -oE 'faces in [0-9]+ ms' <<<"$out" | grep -oE '[0-9]+' | head -1 || true)
  faces=$(grep -oE 'chunks, [0-9]+ faces' <<<"$out" | grep -oE '[0-9]+' | head -1 || true)
  fps=$(grep -oE '\[probe\] fps [0-9]+' <<<"$out" | grep -oE '[0-9]+$' | tail -1 || true)
  sfps=$(grep -oE '\[probe\] settle fps [0-9.]+' <<<"$out" | grep -oE '[0-9.]+$' | tail -1 || true)
  rss=$(grep -E 'maximum resident set size' <<<"$out" | grep -oE '^ *[0-9]+' | tr -d ' ' || true)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$3" "${fill:-?}" "${faces:-?}" "${fps:-?}" \
    "${sfps:-?}" "$(( ${rss:-0} / 1048576 ))" | tee -a "$raw" >&2
}

n=${#labels[@]} first=1
for ((round = 0; round < repeat; round++)); do
  for r in $radii; do
    for ((k = 0; k < n; k++)); do
      i=$(( round % 2 ? n - 1 - k : k ))
      if ((first)); then first=0; elif ((cooldown)); then sleep "$cooldown"; fi
      measure "${labels[$i]}" "${dirs[$i]}" "$r" "${extras[$i]}"
    done
  done
done

# Summary: median (spread = max - min) per label and radius, labels in the order given.
# "fps" is the probe's last half second; "settle fps" is the mean over all --settle frames and is
# the one a gate reads.
printf '| build | radius | runs | fill ms | faces | fps | settle fps | peak RSS MB |\n|:--|--:|--:|--:|--:|--:|--:|--:|\n'
for label in "${labels[@]}"; do
  for r in $radii; do
    awk -F'\t' -v l="$label" -v r="$r" '
      function med(a, c,   i, j, t) {
        for (i = 2; i <= c; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j+1] = a[j]; a[j+1] = t }
        return c % 2 ? a[(c+1)/2] : int((a[c/2] + a[c/2+1]) / 2 + 0.5)
      }
      function cell(a, c,   x) {
        if (!c) return "?"
        x = med(a, c)   # sorts a in place, so a[1] and a[c] are the extremes below
        return c > 1 ? x " (" (a[c] - a[1]) ")" : x
      }
      $1 == l && $2 == r {
        n++; if ($3 != "?") f[++nf] = $3 + 0; if ($5 != "?") p[++np] = $5 + 0
        if ($6 != "?") s[++ns] = $6 + 0
        m[++nm] = $7 + 0; faces = $4
      }
      END { printf "| %s | %s | %d | %s | %s | %s | %s | %s |\n", l, r, n, cell(f, nf), faces, cell(p, np), cell(s, ns), cell(m, nm) }
    ' "$raw"
  done
done
