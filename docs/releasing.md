# Releasing

Loci is built in public: every change lands on `main`, CI checks it, and a release is a tag that GitHub Actions turns into installers and an update that installed copies pick up on their own.

## Loci and Loci Dev

There are two apps, and they never share data.

| | Loci | Loci Dev |
| --- | --- | --- |
| What it is | the app you use every day | the app you work on |
| Identifier | `com.loci.desktop` | `com.loci.desktop.dev` |
| Data folder (macOS) | `~/Library/Application Support/com.loci.desktop` | `~/Library/Application Support/com.loci.desktop.dev` |
| Comes from | a GitHub release, or `npm run install:local` | `npm run app:dev`, `npm run tauri:stable`, `script/build_and_run.sh` |
| Updates | itself, from GitHub Releases | by rebuilding |

Every debug build is Loci Dev whatever the configuration says (`src-tauri/src/flavor.rs`), so a plain `tauri dev` cannot open your real database, and the two run side by side: different Dock entries, notification permissions, window state and loopback endpoints. A release build is Loci Dev when it is built with `--config src-tauri/tauri.dev.conf.json`, as `script/build_and_run.sh` does for agents verifying a change.

`LOCI_DEV_IDENTIFIER=com.loci.desktop.<name>` gives a debug build a data folder of its own, for a second worktree or a QA run. It must start with `com.loci.` and cannot be the installed app's identifier.

To run `main` before it is released, `npm run install:local` (macOS) builds this checkout as Loci and replaces `/Applications/Loci.app`, quitting the running copy first. It is signed with the same identity as releases when this Mac has it, so its permissions survive the next update.

## The changelog

Every user-visible change adds a line under `## [Unreleased]` in [CHANGELOG.md](../CHANGELOG.md), in the same commit. Write it for people who use Loci: what they can do now, not how it was built. At release time that section becomes `## [x.y.z] - date`; its text is the GitHub release's notes and what the update prompt shows.

`node scripts/changelog.mjs check | notes <version> | release <version>` is the tool the release script and workflow use.

## Releasing a version

```sh
npm run release -- 0.2.0
```

`scripts/release.sh` refuses unless you are on a clean `main` that matches `origin/main`, the version is newer, *Unreleased* lists something and the signing secrets are set. If CI has not passed on that commit, it runs `npm run check` first. Then it:

1. sets the version in every file that carries it (`npm run set-version`),
2. turns *Unreleased* into the version's section and updates the compare links,
3. commits `chore: release v0.2.0`, tags `v0.2.0` and pushes both,
4. follows the [release workflow](../.github/workflows/release.yml) to the end.

The workflow checks the tag against `package.json` and the changelog, creates a draft release with the notes, builds macOS (Apple silicon, Intel) and Linux (AppImage, deb) in parallel, uploads each installer, its update and its signature, checks that `latest.json` lists every platform, and publishes. If a job fails, fix it and rerun the failed jobs in Actions: the draft is kept. `gh workflow run release` builds and signs without releasing anything, to try the secrets; the installers are kept as workflow artifacts.

Use semantic versions. While the major version is 0, a minor release may include breaking changes; anything that changes how existing data is read deserves a minor release and a line under *Changed*.

## Updates

An installed Loci asks `https://github.com/Umupa/Loci/releases/latest/download/latest.json` a little after launch and every six hours, shows the new version's notes and, once you agree, installs it and restarts. Only the main window asks. Updates are signed with the update key; Loci accepts only updates whose signature matches the public key in `plugins.updater.pubkey` of `src-tauri/tauri.conf.json`. Losing the private key strands every installed copy, so back it up.

The repository must be public for installed copies to reach `latest.json`.

## Signing

macOS builds are signed with a self-signed identity, "Loci Signing". It is not an Apple Developer ID, so releases are not notarized and macOS asks to confirm the first open. Using one identity for every version keeps the permissions macOS gave an installed Loci (folders, notifications) across updates; an ad hoc signature would change with every build. Without the secret, the workflow signs ad hoc and says so.

## One-time setup

On the Mac that will hold the keys:

```sh
scripts/setup-release.sh
```

It runs, each doing nothing when done already:

- `scripts/signing-cert.sh` creates "Loci Signing" in the login keychain (macOS asks for your password to trust it) and keeps a `.p12` of it there for CI.
- `scripts/update-key.sh` creates the update key pair, keeps the private key and its password in the login keychain ("Loci update key") and writes the public key to `tauri.conf.json`. Commit that change.
- `scripts/ci-secrets.sh` copies both into the repository's Actions secrets: `MACOS_SIGNING_IDENTITY`, `MACOS_SIGNING_PASSWORD`, `TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`.

Back up the keychain items "Loci update key", "Loci update key password", "Loci signing identity" and "Loci signing identity password", for example in a password manager.
