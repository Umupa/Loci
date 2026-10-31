#!/usr/bin/env bash
# The official mentor evaluation: every scenario, mentors and judge on
# Antigravity (agy, judge model pinned), against the evaluation's own QA build,
# cleaned up afterwards. Extra arguments go to the runner (e.g. --scenario sqlite-wal).
#
#   scripts/eval/baseline.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
QA="$HERE/qa-app.sh"
BIN="$("$QA" bin)"

[[ -x "$BIN" ]] || "$QA" build
"$QA" up
trap '"$QA" down' EXIT
cd "$ROOT"
node scripts/eval/run.mjs --app "${LOCI_EVAL_APP_ID:-com.loci.desktop.qa-eval}" --bin "$BIN" --provider agy --judge agy "$@"
