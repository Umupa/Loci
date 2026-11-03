#!/usr/bin/env bash
# Runs remote access end to end against a real relay and device registry:
# hosting and dialling through the relay, pairing with a code, a member
# connecting through the registry, and a tunnel staying up while idle. The
# services are the ones release builds carry (LOCI_RELAY_URL, LOCI_RELAY_KEY,
# LOCI_REGISTRY_URL, LOCI_REGISTRY_KEY), from the environment or from
# src-tauri/remote.env. Takes about three minutes; run it before a release
# that touches src-tauri/src/remote.
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
if [[ -f src-tauri/remote.env ]]; then
	set -a
	source src-tauri/remote.env
	set +a
fi
for name in LOCI_RELAY_URL LOCI_REGISTRY_URL; do
	[[ -n "${!name:-}" ]] || { echo "$name is not set (see src-tauri/remote.env)." >&2; exit 1; }
done

export LOCI_TEST_RELAY="$LOCI_RELAY_URL" LOCI_TEST_REGISTRY="$LOCI_REGISTRY_URL"
[[ -n "${LOCI_RELAY_KEY:-}" ]] && export LOCI_TEST_RELAY_KEY="$LOCI_RELAY_KEY"
[[ -n "${LOCI_REGISTRY_KEY:-}" ]] && export LOCI_TEST_REGISTRY_KEY="$LOCI_REGISTRY_KEY"
cargo test -p loci --lib remote:: -- --ignored --test-threads 4
