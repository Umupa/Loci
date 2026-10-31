#!/usr/bin/env bash
# Creates the key pair that signs updates, once. The private key and its
# password go into the login keychain ("Loci update key", "Loci update key
# password"); the public key is written to plugins.updater.pubkey in
# src-tauri/tauri.conf.json, to commit. Installed copies of Loci accept only
# updates signed with this key, so losing it strands them: back it up, for
# example in a password manager.
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
service="Loci update key"

configured=$(node -p "require('./src-tauri/tauri.conf.json').plugins.updater.pubkey")
if security find-generic-password -s "$service" >/dev/null 2>&1; then
	if [[ -z "$configured" ]]; then
		echo "The keychain has \"$service\" but tauri.conf.json has no public key. Restore the public key that goes with it instead of making a new pair." >&2
		exit 1
	fi
	echo "The update key exists already." >&2
	exit 0
fi
if [[ -n "$configured" ]]; then
	echo "tauri.conf.json has a public key but this keychain has no \"$service\": installed copies trust that key. Restore its private key to the keychain instead of making a new pair." >&2
	exit 1
fi

tmp=$(mktemp -d)
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT
pass=$(/usr/bin/openssl rand -hex 24)
npx --no-install tauri signer generate --ci -p "$pass" -w "$tmp/loci.key" >/dev/null
security add-generic-password -a "$USER" -s "$service" -w "$(cat "$tmp/loci.key")"
security add-generic-password -a "$USER" -s "$service password" -w "$pass"
PUBKEY="$(cat "$tmp/loci.key.pub")" node -e '
const fs = require("fs");
const path = "src-tauri/tauri.conf.json";
const text = fs.readFileSync(path, "utf8");
const next = text.replace(/("pubkey": )""/, (_, key) => key + JSON.stringify(process.env.PUBKEY));
if (next === text) { console.error("could not write the public key to " + path); process.exit(1); }
fs.writeFileSync(path, next);
'
echo "Stored the private key in the login keychain (\"$service\") and wrote the public key to src-tauri/tauri.conf.json. Commit it, and back the private key up." >&2
