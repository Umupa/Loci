#!/usr/bin/env bash
# Creates the self-signed code signing identity "Loci Signing" in the login
# keychain, once; does nothing when it exists. Every release, and the copy
# scripts/install-local.sh installs, is signed with it, so macOS keeps the
# permissions an installed Loci was given across updates. A .p12 of it is
# kept in the keychain too ("Loci signing identity"), for
# scripts/ci-secrets.sh to hand to the release workflow. Back it up: a new
# identity makes installed copies ask for their permissions again.
# macOS asks for your password to trust the certificate for code signing.
set -euo pipefail

name="Loci Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$name\""; then
	echo "The signing identity \"$name\" exists already." >&2
	exit 0
fi

echo "Creating the signing identity \"$name\" (once per Mac); macOS asks for your password." >&2
tmp=$(mktemp -d)
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

pass=$(/usr/bin/openssl rand -hex 24)
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-config "$tmp/cert.conf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
	-out "$tmp/id.p12" -passout "pass:$pass"
security import "$tmp/id.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$keychain" "$tmp/cert.pem"
security add-generic-password -a "$USER" -s "Loci signing identity" -w "$(base64 -i "$tmp/id.p12")"
security add-generic-password -a "$USER" -s "Loci signing identity password" -w "$pass"

echo "Created \"$name\"." >&2
