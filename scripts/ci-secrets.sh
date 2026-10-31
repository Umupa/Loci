#!/usr/bin/env bash
# Puts what the release workflow signs with into the repository's Actions
# secrets, from this Mac's login keychain: the "Loci Signing" identity and
# the key that signs updates. Run it once, and again only when they change.
# Nothing is printed or left on disk.
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

read_secret() {
	if ! security find-generic-password -s "$1" -w 2>/dev/null; then
		echo "The login keychain has no \"$1\". Run scripts/setup-release.sh on the Mac that made it." >&2
		exit 1
	fi
}

identity=$(read_secret "Loci signing identity")
identity_pass=$(read_secret "Loci signing identity password")
key=$(read_secret "Loci update key")
key_pass=$(read_secret "Loci update key password")

printf '%s' "$identity" | gh secret set MACOS_SIGNING_IDENTITY
printf '%s' "$identity_pass" | gh secret set MACOS_SIGNING_PASSWORD
printf '%s' "$key" | gh secret set TAURI_SIGNING_PRIVATE_KEY
printf '%s' "$key_pass" | gh secret set TAURI_SIGNING_PRIVATE_KEY_PASSWORD
echo "Set MACOS_SIGNING_IDENTITY, MACOS_SIGNING_PASSWORD, TAURI_SIGNING_PRIVATE_KEY and TAURI_SIGNING_PRIVATE_KEY_PASSWORD." >&2
echo "Try a signed build without releasing: gh workflow run release" >&2
