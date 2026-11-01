#!/usr/bin/env bash
# The official mentor evaluation: every scenario, mentors on Grok Build inside
# Loci and Grok as judge, against the evaluation's own QA build, cleaned up
# afterwards. Grok is the official provider here; Antigravity is region-blocked
# on this account. Another provider stays an option:
#   LOCI_EVAL_PROVIDER=agy LOCI_EVAL_JUDGE=agy scripts/eval/baseline.sh
# (with LOCI_EVAL_MODEL when its default model is not the one meant).
# Extra arguments go to the runner (e.g. --scenario sqlite-wal).
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
PROVIDER="${LOCI_EVAL_PROVIDER:-grok}"
MODEL="${LOCI_EVAL_MODEL:-}"
# Grok's mentors start on the evaluation's pinned model; another provider keeps its own.
if [[ -z "$MODEL" && "$PROVIDER" == "grok" ]]; then MODEL="grok:deepseek-flash"; fi
ARGS=(--app "${LOCI_EVAL_APP_ID:-com.loci.desktop.qa-eval}" --bin "$BIN"
  --provider "$PROVIDER" --judge "${LOCI_EVAL_JUDGE:-grok}")
if [[ -n "$MODEL" ]]; then ARGS+=(--model "$MODEL"); fi
node scripts/eval/run.mjs "${ARGS[@]}" "$@"
