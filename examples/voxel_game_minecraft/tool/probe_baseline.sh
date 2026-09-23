#!/usr/bin/env bash
# VP0.2 (docs/VOXEL_PACKAGES_PLAN_2026-09-14.md): the probe logs every package move is
# diffed against.
#
#   tool/probe_baseline.sh           # build the debug app, write docs/baseline/*.log
#   tool/probe_baseline.sh --check   # build, run into a temp dir, diff against docs/baseline/
#
# Only `[probe]` lines are kept. --check ignores lines carrying a clock (`ms`) or a frame
# rate (`fps`): those move between runs, everything else must not.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:-write}
base=docs/baseline
if [[ $mode == --check ]]; then out=$(mktemp -d); else out=$base; mkdir -p "$out"; fi

flutter build macos --debug >/dev/null
app=build/macos/Build/Products/Debug/voxel_game_minecraft.app/Contents/MacOS/voxel_game_minecraft
shots=$(mktemp -d)

# A probe gets 240 s. On 2026-09-14 one --stage32 run hung for 9 minutes and the same
# command alone finished in under a minute; a hung probe must fail the run, not stall it.
run() {
  local name=$1
  shift
  perl -e 'alarm 240; exec @ARGV' "$app" --new --seed=42 --frames=300 --settle=10 \
    --screenshot="$shots/$name.png" "$@" 2>&1 | grep -F '[probe]' >"$out/$name.log" || true
  if ! grep -q 'screenshot saved' "$out/$name.log"; then
    echo "PROBE DID NOT FINISH: $name" >&2
    exit 2
  fi
}

# Lines that move between runs: clocks (ms, seconds), frame rates, the temp screenshot path.
# The stage 32 crit count comes from the game's unseeded Random (game.dart `random`), so only
# its number is masked; the line and its 10-40 range stay compared.
stable() { grep -vE '[0-9] ?ms|[0-9] s\b|fps|screenshot saved' "$1" | sed -E 's/crits=[0-9]+/crits=N/'; }

run stage31 --stage31
run stage32 --stage32
run window --radius=8

if [[ $mode == --check ]]; then
  status=0
  for log in stage31 stage32 window; do
    if ! diff <(stable "$base/$log.log") <(stable "$out/$log.log"); then
      echo "DIFFERS: $log" >&2
      status=1
    fi
  done
  [[ $status == 0 ]] && echo "probe logs match docs/baseline/"
  exit $status
fi
echo "wrote $out/{stage31,stage32,window}.log at $(git rev-parse --short HEAD)"
