#!/usr/bin/env bash
# One-time release setup on the maintainer's Mac: the "Loci Signing"
# identity, the update key pair, and the Actions secrets the release
# workflow uses. Each step does nothing when it is done already.
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
scripts/signing-cert.sh
scripts/update-key.sh
scripts/ci-secrets.sh
if ! git diff --quiet src-tauri/tauri.conf.json; then
	echo "Commit the public key: git commit -m 'build: add the update public key' src-tauri/tauri.conf.json" >&2
fi
