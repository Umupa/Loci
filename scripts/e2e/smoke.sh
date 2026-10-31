#!/usr/bin/env bash
# Drives a running Loci through its command line: create a mentor, take in a
# source, save a course, read a lesson, highlight and note a passage, ask the
# mentor about it, mark it read,
# and clean up. Run it against Loci Dev or a QA build, never the installed app:
#
#   LOCI_APP_ID=com.loci.desktop.qa LOCI_BIN="/path/Loci Dev.app/Contents/MacOS/loci" scripts/e2e/smoke.sh
#
# LOCI_SMOKE_PROVIDER picks the mentor's agent CLI (default antigravity);
# LOCI_SMOKE_SEND=0 skips the question to the mentor (no model is run).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCI="${LOCI_BIN:-loci}"
APP="${LOCI_APP_ID:-}"
PROVIDER="${LOCI_SMOKE_PROVIDER:-antigravity}"
# Loci reports providers by id; agy is Antigravity's command.
[[ "$PROVIDER" == "agy" ]] && PROVIDER=antigravity
if [[ -z "$APP" ]]; then
  echo "Set LOCI_APP_ID to the Loci Dev or QA identifier to drive." >&2
  exit 2
fi
if [[ "$APP" == "com.loci.desktop" && "${LOCI_ALLOW_RELEASE:-}" != "1" ]]; then
  echo "Refusing to drive the installed Loci (set LOCI_ALLOW_RELEASE=1 if you mean it)." >&2
  exit 2
fi
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

loci() { "$LOCI" --app "$APP" "$@"; }
step() { printf '\n== %s\n' "$*" >&2; }

step "status"
loci status | jq -e '.ok and .result.running' >/dev/null

step "create a mentor ($PROVIDER, full access)"
MENTOR=$(loci mentors create --template learning-guide --name "Smoke $(date +%s)" \
  --provider "$PROVIDER" --mode full-access | jq -er '.result.id')
trap 'loci mentors delete "$MENTOR" --yes >/dev/null 2>&1 || true' EXIT
loci mentors show "$MENTOR" | jq -e --arg p "$PROVIDER" '.result.provider == $p and .result.mode == "full-access"' >/dev/null

step "take in a source and save a course"
loci sources write --mentor "$MENTOR" --id smoke-scheduling --title "Scheduling, in brief" \
  --path "$HERE/fixtures/scheduling.md" --source-url https://example.com/scheduling | jq -e '.result.saved' >/dev/null
loci courses write --mentor "$MENTOR" --input "$HERE/fixtures/course.json" | jq -e '.result.saved' >/dev/null

step "open a lesson in the reader"
loci reader open --mentor "$MENTOR" --course smoke-scheduling --lesson filtering --switch >/dev/null
loci reader show --mentor "$MENTOR" | jq -e '.result.kind == "course" and .result.lesson.id == "filtering"' >/dev/null
loci reader open --mentor "$MENTOR" --source smoke-scheduling --section Scoring >/dev/null
loci reader show --mentor "$MENTOR" | jq -e '.result.kind == "source" and .result.focus.section == "Scoring"' >/dev/null

if [[ "${LOCI_SMOKE_SEND:-1}" != "0" ]]; then
  if loci models list | jq -e --arg p "$PROVIDER" '.result.harnesses[] | select(.id == $p) | .available' >/dev/null; then
    step "ask the mentor (waits for the reply)"
    loci mentors send "$MENTOR" "In one sentence: what does the scheduler do before scoring nodes? Reply without using tools." \
      --wait --timeout "${LOCI_SMOKE_TIMEOUT:-600}" | jq -e '.result.status == "done" and (.result.text | length > 0)' >/dev/null
  else
    step "skipping the question: $PROVIDER is not available in this Loci"
  fi
fi

step "highlight a passage, note it, count it on its lesson, delete it"
MARK=$(loci annotations add --mentor "$MENTOR" --source smoke-scheduling --section Filtering \
  --quote "not enough free CPU or memory" --note "smoke" \
  | jq -er 'select(.result.saved and .result.annotation.section[-1] == "Filtering") | .result.annotation.id')
loci annotations counts --mentor "$MENTOR" --course smoke-scheduling \
  | jq -e '.result.lessons.filtering == {"highlights":1,"notes":1} and .result.lessons.scoring.highlights == 0' >/dev/null
loci annotations note "$MARK" --note "" | jq -e '.result.annotation.note == ""' >/dev/null
loci annotations list --mentor "$MENTOR" --course smoke-scheduling --lesson filtering | jq -e '.result.annotations | length == 1' >/dev/null
loci reader open --mentor "$MENTOR" --source smoke-scheduling --quote "the pod is bound to the best one" >/dev/null
loci reader show --mentor "$MENTOR" | jq -e '.result.focus.quote == "the pod is bound to the best one"' >/dev/null
loci annotations delete "$MARK" --yes | jq -e '.result.deleted' >/dev/null
loci annotations counts --mentor "$MENTOR" --source smoke-scheduling | jq -e '.result.highlights == 0' >/dev/null

step "mark the lesson read"
loci courses lesson smoke-scheduling filtering --mentor "$MENTOR" --status read | jq -e '.result.status == "read"' >/dev/null
loci courses read --mentor "$MENTOR" smoke-scheduling | jq -e '.result.progress.filtering == "mastered"' >/dev/null

step "clean up"
loci mentors delete "$MENTOR" --yes | jq -e '.result.deleted' >/dev/null
trap - EXIT
echo "smoke test passed" >&2
