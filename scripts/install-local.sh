#!/usr/bin/env bash
# Builds Loci from this checkout as the installed app (com.loci.desktop, your
# real data) and puts it in /Applications, replacing the copy there. Use it
# to run main before it is released; releases then update it as usual. For
# working on Loci, use Loci Dev instead (npm run app:dev), which keeps its
# own data. macOS only.
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
[[ "$(uname)" == Darwin ]] || { echo "install-local.sh is for macOS." >&2; exit 1; }

args=(build --bundles app)
if security find-identity -v -p codesigning | grep -q '"Loci Signing"'; then
	args+=(--config '{"bundle":{"macOS":{"signingIdentity":"Loci Signing"}}}')
else
	echo "No \"Loci Signing\" identity (scripts/signing-cert.sh makes it): signing ad hoc, so macOS asks for permissions again after each install." >&2
fi
npx --no-install tauri "${args[@]}"

built="target/release/bundle/macos/Loci.app"
installed="/Applications/Loci.app"
if pgrep -f "$installed/Contents/MacOS/loci" >/dev/null; then
	echo "Quitting the running Loci…" >&2
	osascript -e 'tell application id "com.loci.desktop" to quit' || true
	for _ in $(seq 40); do
		pgrep -f "$installed/Contents/MacOS/loci" >/dev/null || break
		sleep 0.5
	done
fi
rm -rf "$installed"
ditto "$built" "$installed"
open "$installed"
echo "Installed $(node -p "require('./package.json').version") ($(git rev-parse --short HEAD)) to $installed." >&2
