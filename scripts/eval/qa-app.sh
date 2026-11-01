#!/usr/bin/env bash
# The evaluation's own QA build of Loci: build it, start it, stop it and
# remove everything it wrote. It only ever touches its own identifier, so other
# QA apps (such as com.loci.desktop.qa-v03) keep running.
#
#   scripts/eval/qa-app.sh build   # release bundle "Loci Eval QA" (com.loci.desktop.qa-eval)
#   scripts/eval/qa-app.sh up      # start it and wait for its command line
#   scripts/eval/qa-app.sh down    # quit it and delete its data and the ~/Loci-Dev folders it made
#   scripts/eval/qa-app.sh bin     # print the path of its loci executable
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ID="${LOCI_EVAL_APP_ID:-com.loci.desktop.qa-eval}"
NAME="${LOCI_EVAL_APP_NAME:-Loci Eval QA}"
APP="$ROOT/target/release/bundle/macos/$NAME.app"
BIN="$APP/Contents/MacOS/loci"
STATE="${TMPDIR:-/tmp}/loci-eval-$ID"
case "$ID" in com.loci.desktop|com.loci.desktop.dev|com.loci.desktop.qa-v03) echo "Refusing to manage $ID" >&2; exit 2;; esac

running_pid() { pgrep -f "^$APP/Contents/MacOS/" | head -1 || true; }

case "${1:-}" in
  build)
    cd "$ROOT"
    npx tauri build --bundles app --config src-tauri/tauri.dev.conf.json \
      --config "{\"identifier\":\"$ID\",\"productName\":\"$NAME\"}"
    ;;
  up)
    [[ -x "$BIN" ]] || { echo "No build at $APP; run: $0 build" >&2; exit 2; }
    mkdir -p "$STATE"
    # What already is in ~/Loci-Dev, so "down" removes only what this app adds.
    [[ -f "$STATE/loci-dev-before" ]] || { ls -1 "$HOME/Loci-Dev" 2>/dev/null || true; } > "$STATE/loci-dev-before"
    if [[ -z "$(running_pid)" ]]; then open -n "$APP"; fi
    for _ in $(seq 1 60); do
      if "$BIN" --app "$ID" status 2>/dev/null | grep -q '"running":true'; then echo "$ID is up" >&2; exit 0; fi
      sleep 1
    done
    echo "$ID did not come up" >&2; exit 3
    ;;
  down)
    pid="$(running_pid)"
    if [[ -n "$pid" ]]; then
      osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || kill "$pid" || true
      for _ in $(seq 1 20); do [[ -z "$(running_pid)" ]] && break; sleep 0.5; done
      pid="$(running_pid)"; [[ -n "$pid" ]] && kill -9 "$pid" || true
    fi
    for dir in "$HOME/Library/Application Support/$ID" "$HOME/Library/Caches/$ID" "$HOME/Library/WebKit/$ID" \
               "$HOME/Library/Preferences/$ID.plist" "$HOME/Library/Saved Application State/$ID.savedState" "$HOME/Library/HTTPStorages/$ID"; do
      [[ -e "$dir" ]] && rm -rf "$dir"
    done
    # A QA build's mentors root is ~/Loci-Dev-<last identifier segment> (see
    # mentor_store::paths); it holds the mentors, their sources and their cloned
    # repos, and belongs to this app alone. The installed Loci's ~/Loci is never touched.
    case "$ID" in
      com.loci.desktop.qa-*)
        QA_ROOT="$HOME/Loci-Dev-${ID##*.}"
        if [[ "$QA_ROOT" != "$HOME/Loci-Dev-" && -d "$QA_ROOT" ]]; then rm -rf "$QA_ROOT"; echo "removed $QA_ROOT" >&2; fi
        ;;
    esac
    if [[ -f "$STATE/loci-dev-before" && -d "$HOME/Loci-Dev" ]]; then
      # Other Loci Dev/QA builds share ~/Loci-Dev: remove a new folder only when
      # it holds no files (a mentor's default workdir, made with an empty repos/ before --workdir moved it);
      # name anything else so it can be checked by hand.
      while IFS= read -r entry; do
        grep -qxF "$entry" "$STATE/loci-dev-before" && continue
        dir="$HOME/Loci-Dev/$entry"
        if [[ -d "$dir" && -z "$(find "$dir" -type f ! -name .DS_Store -print -quit)" ]]; then
          echo "removing empty ~/Loci-Dev/$entry" >&2; rm -rf "$dir"
        else
          echo "left ~/Loci-Dev/$entry (not empty; check whether this run made it)" >&2
        fi
      done < <(ls -1 "$HOME/Loci-Dev")
    fi
    rm -rf "$STATE" "${TMPDIR:-/tmp}/loci-eval"
    echo "$ID is down and cleaned up" >&2
    ;;
  bin) echo "$BIN" ;;
  *) sed -n '2,10p' "$0" >&2; exit 2 ;;
esac
