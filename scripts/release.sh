#!/usr/bin/env bash
# Releases version <x.y.z> from main. It checks that main is clean, pushed
# and green, turns CHANGELOG.md's Unreleased section into "## [x.y.z]", sets
# the version everywhere, commits "chore: release vx.y.z", tags and pushes.
# The tag starts .github/workflows/release.yml, which builds, signs, uploads
# and publishes the release; this script follows it to the end. Installed
# copies of Loci offer the update at their next check.
set -euo pipefail

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "usage: scripts/release.sh <version, like 0.2.0>" >&2
	exit 1
fi
tag="v$version"
current=$(node -p "require('./package.json').version")

fail() {
	echo "$1" >&2
	exit 1
}

[[ "$(git branch --show-current)" == main ]] || fail "Release from main only."
git diff --quiet && git diff --cached --quiet || fail "Commit or stash your changes first."
git fetch -q origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main and origin/main differ: pull or push first."
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "$tag exists already."
node -e '
const [a, b] = process.argv.slice(1).map((v) => v.split(".").map(Number));
const newer = a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
// The first release keeps the version the code already has.
process.exit(newer >= 0 ? 0 : 1);
' "$version" "$current" || fail "$version is older than $current, the current version."
node scripts/changelog.mjs check || fail "Add what changed under \"## [Unreleased]\" in CHANGELOG.md first."
[[ -n "$(node -p "require('./src-tauri/tauri.conf.json').plugins.updater.pubkey")" ]] ||
	fail "There is no update public key yet. Run scripts/setup-release.sh once."
secrets=$(gh secret list --json name --jq '.[].name')
for secret in TAURI_SIGNING_PRIVATE_KEY TAURI_SIGNING_PRIVATE_KEY_PASSWORD MACOS_SIGNING_IDENTITY MACOS_SIGNING_PASSWORD; do
	grep -qx "$secret" <<<"$secrets" || fail "The repository has no $secret secret. Run scripts/setup-release.sh once."
done

# The release commit only changes versions and the changelog, so a green CI
# run on HEAD stands for it.
ci=$(gh run list --workflow CI --commit "$(git rev-parse HEAD)" --json status,conclusion \
	--jq 'map(select(.status == "completed")) | .[0].conclusion // empty')
if [[ "$ci" != success ]]; then
	echo "CI has not passed on this commit (${ci:-no finished run}); running the checks here…" >&2
	npm run check
fi

[[ "$version" == "$current" ]] || npm run -s set-version -- "$version" >/dev/null
node scripts/changelog.mjs release "$version"
git commit -q -m "chore: release $tag" -- package.json package-lock.json Cargo.toml Cargo.lock src-tauri/tauri.conf.json CHANGELOG.md
git tag "$tag"
git push -q origin main "$tag"

# The run shows up a few seconds after the push.
run=""
for _ in $(seq 30); do
	run=$(gh run list --workflow Release --branch "$tag" --limit 1 --json databaseId --jq '.[0].databaseId // empty')
	[[ -n "$run" ]] && break
	sleep 2
done
if [[ -z "$run" ]]; then
	echo "Pushed $tag. The release runs in GitHub Actions: gh run list --workflow Release" >&2
	exit 0
fi
echo "Building, signing and publishing $tag in GitHub Actions (about 20 minutes)…" >&2
if ! gh run watch "$run" --exit-status --interval 30 >/dev/null; then
	fail "The release did not finish: gh run view $run --log-failed. Fix it, then rerun the failed jobs in Actions; the draft $tag is kept."
fi
echo "Released $tag: $(gh release view "$tag" --json url --jq .url)" >&2
