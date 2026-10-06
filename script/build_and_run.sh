#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--debug|--logs|--telemetry|--verify]\n' "$0"
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

MODE="${1:-run}"
case "$MODE" in
  -h|--help) usage; exit 0 ;;
  run|--debug|--logs|--telemetry|--verify) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/target/release/bundle/macos/Loci.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/loci"
cd "$ROOT_DIR"

# Stop only GUI executables built in this checkout.
for task_pid in $(pgrep -x loci || true); do
  task_command="$(ps -p "$task_pid" -o comm= || true)"
  case "$task_command" in
    "$ROOT_DIR"/target/*/Loci.app/Contents/MacOS/loci|"$ROOT_DIR"/target/debug/loci|"$ROOT_DIR"/target/release/loci)
      kill -TERM "$task_pid"
      ;;
  esac
done

npm run tauri -- build --bundles app

case "$MODE" in
  --debug)
    exec lldb -- "$APP_BINARY"
    ;;
  --logs)
    /usr/bin/open -n "$APP_BUNDLE"
    exec /usr/bin/log stream --info --style compact --predicate 'process == "loci"'
    ;;
  --telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.loci.desktop"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    for task_attempt in {1..20}; do
      for task_pid in $(pgrep -x loci || true); do
        if [[ "$(ps -p "$task_pid" -o comm= || true)" == "$APP_BINARY" ]]; then
          printf 'Loci started (PID %s): %s\n' "$task_pid" "$APP_BUNDLE"
          exit 0
        fi
      done
      sleep 0.5
    done
    printf 'Loci did not remain running after launch.\n' >&2
    exit 1
    ;;
  run)
    /usr/bin/open -n "$APP_BUNDLE"
    ;;
esac
